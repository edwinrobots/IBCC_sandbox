classdef DynIbccVb < combiners.bcc.IbccVb
    %DYNIBCCVB Dynamic IBCC-VB
    %   For base classifiers that change. Uses a dynamic
    %   dirichlet-multinomial model to determine the confusion matrices
    %   after each data point.
    
    properties
        Wmean0; %weights - the state object; related to posterior Alphas
        P0; %covariance of the weights
        
        Alpha_t = [];
        
        sepConfMatrix = false; %treat the expected class label as a continuous input variable (false) or separate into two binary inputs woth separate covariances
        initAll = false;
        
        Wmean_filter;
        P_filter;
        k_t;
        q_t;
        eta_tminus;
        r_tminus;
        K_kal;
        bigLambdaBar;
        smallLambdaBar;
        delta_Wmean;
        delta_Ppost;
        h;
        C3;
        
        minUpdateSize = 0;%0.005;
        minUpdateSize1 = 0;%0.001;
        minUpdateSize3 = 0;%0.001;
        minUpdateSize2 = 0%;0.02;
        
%         initialET = [];
%         initialC = [];
    end
    
    methods(Static)
        function sl = shortLabel
            sl = 'DynIbccVb';
        end      
        function sl = shortLabelSep
            sl = 'DynIbccVb-sepCov';
        end
        function sl = shortLabelInitAll
            sl = 'DynIbccVB-initall';
        end   
    end
    
    methods
        
        function obj = DynIbccVb(bccSettings, nAgents, K_kal, targets, agents, nClasses, nScores)
            obj@combiners.bcc.IbccVb(bccSettings, nAgents, K_kal, targets, agents, nClasses, nScores);
            obj.label = 'Dynamic VB I.B.C.C.'; 
            obj.Alpha = [];            
        end        
        
        function [Wmean0 P0] = alphaToStateDist(obj, Alpha0, C) 
            %convert Alpha to distribution over state variables W with mean
            %Wmean0 and covariance P0
            Wmean0 = log(Alpha0./(repmat(sum(Alpha0, 2), 1, obj.nScores)-Alpha0)); %one cell entry per data point
            P0 = zeros(obj.nClasses, obj.nClasses, length(C{1}), obj.nScores); %one cell for each class
            for s=1:obj.nScores
                for j=1:obj.nClasses
                    P0(j,j,:,s) = 1./Alpha0(j,s,1) + 1./(sum(Alpha0(j,:,1), 2)-Alpha0(j,s,1));
                end
            end
        end
        
        %modify this to also initialise the Wmean and P, and dynamic lnP
        function [lnPi, lnP, ET, Tind] = initVariables(obj, C, nAssets)  
            
            obj.minUpdateSize2 = obj.minUpdateSize * obj.nClasses * obj.nScores * obj.nClasses;
            obj.minUpdateSize = obj.minUpdateSize * obj.nClasses;
            
            [obj.Wmean0 obj.P0] = obj.alphaToStateDist(obj.Alpha0, C);
            
            if nargin < 5
                nAssets = length(obj.targets);
            end
                        
            if sum(obj.Nu0)==0
                obj.Nu0 = 0.5;
            end
            if isempty(obj.lnK)
                nu = obj.Nu0;
                for j=1:obj.nClasses
                    nu(j) = nu(j) + sum(obj.targets==j);
                end
                lnP = psi(nu) - psi(sum(nu)); 
            else
                lnP = obj.lnK;
            end
                    
            ET = initET(obj, C, nAssets, lnP);
            
            unknownIdxs = ~ismember(C{2}, find(obj.targets>0));
            Cknown = C;
            Cknown{3}(unknownIdxs) = 0;
            
            if obj.initAll
                lnPi = obj.expectedLnPi(C, ET);
%                 obj.initialC = C;
            else
                lnPi = obj.expectedLnPi(Cknown, ET);
%                 obj.initialC = Cknown;
            end
            Tind = ET;
%             obj.initialET = ET;
        end
        
        function r_tminus = calculateR(obj, ET_n, P_tminus)
            r_tminus = zeros(1, obj.nScores);
            for s=1:obj.nScores
                r_tminus(1, s) = ET_n' * P_tminus(:,:,s) * ET_n;
            end
        end
        
        function y = getAlpha(obj, c, k_t, m_t, h, i)
            y = zeros(1, obj.nScores); %from C
            if c==0 %unknown
                y = k_t ./ m_t;
            else
                y(c) = 1;
            end             
        end
        
        function AlphaBundle = updateAlpha(obj, C, ET, ~, ~)
            nResp = length(C{1});
            if isempty(obj.Alpha)
                obj.Alpha = zeros(obj.nClasses, obj.nScores, length(C{1}));
                obj.Alpha_t = zeros(obj.nScores, nResp); %for the distribution over eta_t given all c and t
            elseif iscell(obj.Alpha)
                obj.Alpha_t = obj.Alpha{2};
                obj.Alpha = obj.Alpha{1};                
            end

            nClassifiers = length(obj.C1_desparse);%max(C{1});                
       
            startFrom = 1;
            backTo = 1;
            prevObs = zeros(1, nClassifiers);    
            subsObs = zeros(1, nClassifiers);
            
            nNewPoints = nResp - size(obj.q_t,2);
            
%             obj.q_t = [obj.q_t zeros(obj.nScores,nNewPoints)];
            obj.q_t = [obj.q_t zeros(1,nNewPoints)];
            obj.eta_tminus = [obj.eta_tminus; zeros(nNewPoints, obj.nScores)];
            obj.r_tminus = [obj.r_tminus; zeros(nNewPoints, obj.nScores)];
            r_tpost = zeros(nResp, obj.nScores);
            obj.K_kal = [obj.K_kal zeros(obj.nClasses, nNewPoints, obj.nScores)];
            obj.h = [obj.h zeros(obj.nClasses, nNewPoints)];
            
            I = eye(obj.nClasses, obj.nClasses);
            
            %previous observation for each classifier. 0 means no
            %observations
            Wmean_post = zeros(obj.nClasses, obj.nScores, nResp);
            P_post = zeros(obj.nClasses, obj.nClasses, obj.nScores, nResp);
            
            eta_tpost = zeros(nResp, obj.nScores);

            R = zeros(nResp, obj.nScores);

            if isempty(obj.k_t)
                obj.k_t = zeros(nResp, obj.nScores);
               % obj.Wmean_filter = zeros(obj.nClasses, obj.nScores, nResp);
               % obj.P_filter = zeros(obj.nClasses, obj.nClasses, obj.nScores, nResp);
            end
            
            changedFlags = ones(1,nResp);
                                    
            %FORWARD PASS
            for n=startFrom:nResp             
                k = obj.C1_desparse(n);
                tminus = prevObs(k);
                
                c = C{3}(n);
                i = C{2}(n);
                h = ET(:,i);
                if tminus==0
                    Wmean_tminus = obj.Wmean0(:,:,n);
                    P_tminus = reshape(obj.P0(:,:,n,:), obj.nClasses, obj.nClasses, obj.nScores);
                    q_tminus = 0;
                    %updateSize2 = obj.minUpdateSize2;
                else
                    Wmean_tminus = Wmean_post(:,:,tminus);
                    P_tminus = P_post(:,:,:,tminus);
                    q_tminus = obj.q_t(tminus);
                    %if sum(sum(sum(obj.P_filter)))==0
		    %  updateSize2 = obj.minUpdateSize2;
		    %else
                    %    updateSize2 = sum(sum(sum(abs(P_tminus - obj.P_filter(:,:,:,tminus)))));
                    %end
                end    
                
                eta_tminus = h' * Wmean_tminus; 
                
                %updateSize3 = obj.minUpdateSize3;
                %if updateSize2 < obj.minUpdateSize2 
                %    if n<=length(obj.C3) && c == obj.C3(n)
                %        updateSize1 = sum(abs(eta_tminus - obj.eta_tminus(n,:)));
                %        if updateSize1 < obj.minUpdateSize1

%                            updateSize3 = sum(abs(h - obj.h(:,n)));
 %                       end
  %                  end                    
   %             end

    %            if  updateSize3 < obj.minUpdateSize3 && (~changedFlags(tminus) || tminus==0) 
     %               prevObs(k) = n;
      %              Wmean_post(:,:,n) = obj.Wmean_filter(:,:,n);
       %             P_post(:,:,:,n) = obj.P_filter(:,:,:,n);
        %            changedFlags(n) = false;
%                     display(['skipping in forward pass 2: ' num2str(i) ', ' num2str(k)]);
         %           continue;
          %      end    
                                
%                 P_tminus(:,:,:) = P_tminus(:,:,:) + repmat(reshape(obj.settings.changeRateMod*q_t, [1,1,obj.nScores]), size(P_tminus,1), size(P_tminus,2));
                P_tminus(:,:,:) = P_tminus(:,:,:) + obj.settings.changeRateMod*q_tminus;
                P_tminus_r = reshape(P_tminus(:,:,:), size(P_tminus,1), size(P_tminus,2)*size(P_tminus,3));
                r_tminus = h' * reshape(h'*P_tminus_r, size(P_tminus,2), size(P_tminus,3));                

                k_t = (1./r_tminus) .* (1+exp(eta_tminus));
                                
                %Also need to check q_tminus separately or does it come
                %under r_tminus?
           %     if updateSize2 < obj.minUpdateSize2 && n<=length(obj.C3) && ...
           %             c == obj.C3(n) && size(obj.k_t,1)>=n  %&& (~changedFlags(tminus) || tminus==0) 
           %         updateSize = max(abs((obj.k_t(n,:)-k_t)./k_t));
           %         if updateSize < obj.minUpdateSize
           %             %don't bother to do a proper update, it's too small
           %             prevObs(k) = n;
           %             Wmean_post(:,:,n) = obj.Wmean_filter(:,:,n);
           %             P_post(:,:,:,n) = obj.P_filter(:,:,:,n);
           %             changedFlags(n) = false;
%          %               display(['skipping in forward pass 1: ' num2str(i) ', ' num2str(k)]);
           %             continue;
           %         end 
           %     end                  
                obj.h(:,n) = h;
                obj.eta_tminus(n,:) = eta_tminus; 
                obj.r_tminus(n, :) = r_tminus;
                obj.k_t(n,:) = k_t;                

                m_t = k_t .* (1+exp(-obj.eta_tminus(n,:)));

                if sum(isnan(k_t))>0
                    display('update !!!');
                end
                y = obj.getAlpha(c, k_t, m_t, h, i);                    

                %estimate posteriors of eta and r
                denom = m_t-k_t+sum(y)-y;
                eta_tpost(n,:) = log((k_t+y) ./ denom);
                r_tpost(n,:) = (1./(k_t+y)) + (1./(m_t-k_t+sum(y)-y));

%                 u_tpost = (k_t+y) .* (m_t-k_t+sum(y)-y) ./ (m_t+sum(y)).^2;
%                 u_tminus = (k_t) .* (m_t-k_t) ./ (m_t).^2;
                u_tpost = prod((k_t+y) ./ (m_t+sum(y)));
                u_tminus  = prod(k_t./m_t);
                
                obj.q_t(n) = (u_tpost>u_tminus) * (u_tpost-u_tminus);
%                 obj.q_t(unonzero,n) = u_tpost(unonzero)-u_tminus(unonzero);
                if c==0 
                    labelUncertainty = y.*(1-y);
%                     obj.q_t(:,n) = obj.q_t(:,n) + labelUncertainty;                    
                    obj.q_t(n) = obj.q_t(n) + sum(labelUncertainty);      
                end

                corrections = isinf(r_tpost(n,:));
                r_tpost(n,corrections) = obj.r_tminus(n,corrections);
                
                tmp = reshape(P_tminus(:,:,:), size(P_tminus,1), size(P_tminus,2)*size(P_tminus,3))' * h;
                tmp = tmp ./ reshape( repmat(obj.r_tminus(n,:), size(P_tminus,1), 1), obj.nScores*size(P_tminus,1), 1);               
                obj.K_kal(:,n,:) = reshape(tmp, [size(obj.K_kal,1), 1, size(obj.K_kal,3)]);
                
                R(n,:) = 1-(r_tpost(n,:)./obj.r_tminus(n,:));
                Wmean_post(:,:,n) = Wmean_tminus + ...
                    reshape(obj.K_kal(:,n,:),size(obj.K_kal,1),size(obj.K_kal,3)).*repmat((eta_tpost(n,:) - obj.eta_tminus(n,:)), size(obj.K_kal,1),1);

                Kh = reshape(obj.K_kal(:,n,:), 1,obj.nClasses*obj.nScores)' * h';
                Kh_idxs = 1:obj.nClasses;
                
                %calculate weight updates
                for s=1:obj.nScores
                    P_post(:,:,s,n) = P_tminus(:,:,s) - (Kh(Kh_idxs, :) *...
                        P_tminus(:,:,s) .* R(n,s));
                    Kh_idxs = Kh_idxs + obj.nClasses;
                end              

                prevObs(k) = n;
            end
            
            %obj.Wmean_filter = Wmean_post;
            %obj.P_filter = P_post;
                   
            if isempty(obj.bigLambdaBar)
                %used to be nClassifiers, could use a lot of memory
                obj.bigLambdaBar = zeros(obj.nClasses, obj.nClasses, obj.nScores, nResp);
                obj.smallLambdaBar = zeros(obj.nClasses, obj.nScores, nResp);
                obj.delta_Wmean = zeros(obj.nClasses, obj.nScores, nResp);
                obj.delta_Ppost = zeros(obj.nClasses, obj.nClasses, obj.nScores, nResp);
            end

            r_tvb = zeros(obj.nClasses, obj.nScores);
                
            %BACKWARD PASS               
            for n=fliplr(backTo:nResp)
                k = obj.C1_desparse(n);
                tplus = subsObs(k);
%                 tminus = find(obj.C1_desparse(1:n-1)==k);
                subsObs(k) = n;
                
                i = C{2}(n);
                h = ET(:,i);

                if tplus==0
                    bigLambdaHat = zeros(obj.nClasses, obj.nClasses, obj.nScores);
                    smallLambdaHat = zeros(obj.nClasses, obj.nScores);
                else
                    bigLambdaHat = obj.bigLambdaBar(:,:,:,tplus);
                    smallLambdaHat = obj.smallLambdaBar(:,:,tplus);
                end

%                if ~changedFlags(n) && (tplus<=n || changedFlags(tplus)==0) 
%                    if  sum(obj.Alpha_t(:, n)>0)==obj.nScores
%                     display(['skipping in backward pass: ' num2str(i) ', ' num2str(k)]);
%                    continue;
%                    end
%                else
%                     display(['not skipping in backward pass: ' num2str(i) ', ' num2str(k)]);
%                    changedFlags(n) = 2+changedFlags(n);
%                end

                for s=1:obj.nScores  
                    obj.delta_Wmean(:,s,n) = P_post(:,:,s,n)*smallLambdaHat(:, s);
                    obj.delta_Ppost(:,:,s,n) = P_post(:,:,s,n)*bigLambdaHat(:,:,s)*(P_post(:,:,s,n)');
                end

                r_tN = zeros(1,obj.nScores);                
                    
                Wmean_post(:,:,n) = Wmean_post(:,:,n) - obj.delta_Wmean(:,:,n);
                
                %errors = Wmean_post(:,:,n)<0;
                %if sum(sum(errors)) > 0
                %    Wmean_post(errors,n) = 0;
                %    display(['correcting Wmean_post errors for ' num2str(k) ' data point ' num2str(n)]);
                %end
                
                P_post(:,:,:,n) = P_post(:,:,:,n) - obj.delta_Ppost(:,:,:,n);
                
                %errors = P_post(:,:,:,n)<0;
                %if sum(sum(sum(errors))) > 0
                %    P_post(errors,n) = 0;
                %    display(['correcting P_post errors for ' num2str(k) ' data point ' num2str(n)]);
                %end
                
                invA = 1./obj.r_tminus(n,:);
                z = eta_tpost(n,:) - obj.eta_tminus(n,:);
                hinvAz = h* (z .* invA);
                
                R(n,:) = 1-(r_tpost(n,:)./obj.r_tminus(n,:));
                hinvAR = h*(invA .* R(n,:));
                                
                for s=1:obj.nScores                                                
                            
                    eta_tpost(n,s) = h' * Wmean_post(:,s,n);
                    
                    B = I - obj.K_kal(:,n,s)*h';                
                    r_tpost(n, s) = h' * P_post(:,:,s,n) * h;
                    
                    obj.smallLambdaBar(:,s,n) = -hinvAz(:,s) + B'*smallLambdaHat(:,s);
                    obj.bigLambdaBar(:,:,s,n) = hinvAR(:,s)*h' + B'*bigLambdaHat(:,:,s)*B;


                    
%                     if sum(sum(sum(isinf(obj.bigLambdaBar(:,:,:,n))))) > 0 
%                         display('oh noes 2 :(');
%                     end
                    
                    %Values for the VB updates: calculate the alphas
                    %each class by setting inputs to 1 for each class
                    r_tvb(:,s) = diag(P_post(:,:,s,n));
                    r_tN(s) = h' * P_post(:,:,s,n) * h;                    
                end
                k_tN = (1./r_tN) .* (1+exp(h'*Wmean_post(:,:,n)));
                k_tvb = (1./r_tvb) .* (1+exp(Wmean_post(:,:,n)));
                
                invalidK = sum(k_tvb<0)>0;
                
                if invalidK
                    display(['negative alpha: ' num2str(i) ', worker ' num2str(k)...
                        ' with change flags ' num2str(changedFlags(n)) ...
                        ', subsequent i: ' num2str(tplus) ' which had change flags ' ...
                        num2str(changedFlags(tplus))]);
                    display(['chain ' num2str(changedFlags(obj.C1_desparse==k))]);
                end
                if sum(isnan(k_tvb)) > 0 
                    display('hello :(');
                end
                if sum(sum(k_tvb))==0
                    display('going to cause an error through dodgy backward pass');
                end
                
%                updateSize = max(abs(sum(obj.Alpha(:,:,n)-k_tvb,1)./sum(k_tvb,1)));
%           
%                if updateSize < obj.minUpdateSize | invalidK
%                    changedFlags(n) = 0;
%                else                    
%                     display(['smoothy ' num2str(updateSize)]);%
%                    changedFlags(n) = 2+changedFlags(n);
%		    obj.P_filter(:,:,:,n) = 0; %reset this so that we dont skip this next time
%                end
                    
                if ~invalidK
%		    obj.P_filter(:,:,:,n) = 0; %reset this so that we dont skip this next time
                    obj.Alpha_t(:, n) = k_tN;
                    obj.Alpha(:, :, n) = k_tvb;
                else
		    display('Invalid Alpha: keeping the old values, which is:');
		    obj.Alpha_t(:, n)
                end                    
                
            end       
            
            AlphaBundle = {obj.Alpha obj.Alpha_t};
            obj.C3 = C{3};
        end

        function [AlphaJPr AlphaJ] = lnPiPrior(obj, C, lnPi, ET)  
            Eta = lnPi - repmat(sum(lnPi, 2), 1, obj.nScores) + lnPi;
            AlphaJPr = zeros(obj.nScores, length(C{1})); %for the distribution over eta_t given the previous eta_t
            AlphaJ = zeros(obj.nScores, length(C{1})); %for the distribution over eta_t given the previous eta_t and all c and t
            Wmean0 = obj.Wmean0;
            P0 = obj.P0;

            nClassifiers = max(C{1});

            I = eye(obj.nClasses, obj.nClasses);
            
            %previous observation for each classifier. 0 means no
            %observations
            nResp = length(C{1});
            
            prevObs = sparse(1, nClassifiers);            
            Wmean_post = zeros(obj.nClasses, obj.nScores, nResp);
            r_tminus = zeros(nResp, obj.nScores);
            K_kal = zeros(obj.nClasses, nResp, obj.nScores);
            q_t = zeros(nClassifiers, obj.nScores);
            eta_tpost = zeros(nResp, obj.nScores);
            r_tpost = zeros(nResp, obj.nScores);       
            R = zeros(nResp, obj.nScores);
            P_post = zeros(obj.nClasses, obj.nClasses, obj.nScores, nResp);            
            %FORWARD PASS
            for n=1:nResp
                k = C{1}(n);
                tminus = prevObs(k);
                i = C{2}(n);
                h = ET(:,i);
                if tminus==0
                    Wmean_tminus = Wmean0(:,:,n);
                    P_tminus = reshape(P0(:,:,n,:), obj.nClasses, obj.nClasses, obj.nScores);
                else
                    Wmean_tminus = Wmean_post(:,:,tminus);
                    P_tminus = P_post(:,:,:,tminus);
                end    

                %k is a row vector. Each column corresponds to a score
                eta_tminus = h' * Wmean_tminus;                
                
                for s=1:obj.nScores
                    P_tminus(:,:,s) = P_tminus(:,:,s) + q_t(k, s)*I;
                    r_tminus(n, s) = h' * P_tminus(:,:,s) * h;
                end
                
                k_t = (1./r_tminus(n,:)) .* (1+exp(eta_tminus));
                m_t = k_t .* (1+exp(-eta_tminus));                  

                AlphaJPr(:,n) = k_t; 
                if sum(isnan(k_t))>0
                    display('oh no!');
                end
                
                c = C{3}(n);                
                y = k_t ./ m_t;
                labelUncertainty = y.*(1-y); 
                
                if c~=0
                    display('i do not think we should be here');
                    y = zeros(1, obj.nScores); %from C   
                    y(c) = 1;
                    labelUncertainty = 0; %for the prior we are assuming the label is unknown
                end
                
                %estimate posterior of r
                r_tpost(n,:) = (1./(k_t+y)) + (1./(m_t-k_t+1-y));

                prevObs(k) = n;                  

                %estimate posteriors of eta and r
                u_tpost = (k_t+y) .* (m_t-k_t+1-y) ./ (m_t+1).^2;
                u_tminus = (k_t) .* (m_t-k_t) ./ (m_t).^2;
                q_t(k,:) = max([u_tpost-u_tminus; zeros(1,obj.nScores)], [], 1) + labelUncertainty;
                
                AlphaJ(:,n) = k_t+y;
                
                eta_tpost(n,:) = h'*Eta(:,:,n);
                
                %calculate weight updates
                for s=1:obj.nScores
                    if isinf(r_tpost(n,s))
                        r_tpost(n,s) = r_tminus(n,s); %near enough - a single update in the same direction will have minimal change
                    end
                    K_kal(:,n,s) = P_tminus(:,:,s)' * h / r_tminus(n,s); 
                    R(n,s) = 1-(r_tpost(n,s)./r_tminus(n,s));
                    Wmean_post(:,s,n) = Wmean_tminus(:,s) + K_kal(:,n,s)*(eta_tpost(n,s) - eta_tminus(s));
                    P_post(:,:,s,n) = P_tminus(:,:,s) - K_kal(:,n,s)*h'*P_tminus(:,:,s)*R(n,s);
                    if sum(isnan(P_post(:,:,s,n)))>0
                        display('oh no!!');
                    end
                    
                    if sum(isnan(Wmean_post(:,s,n)))
                        display('oh no!!!');
                    end
                end                
            end                
        end
        
        function [ElnPiBundle, AlphaBundle] = expectedLnPi(obj, C, ET, agentIdx, OldPostAlpha)
            %specifying agentIdx means we only update for that agent from
            %the last score in C and use the given counts for others

            if nargin < 5
                AlphaBundle = obj.updateAlpha(C, ET);
            else
                AlphaBundle = obj.updateAlpha(C, ET, agentIdx, OldPostAlpha);                  
            end
        
            Alpha = AlphaBundle{1};
            Alpha_t = AlphaBundle{2};
            
            try
                normTerm = psi(sum(Alpha,2));
                ElnPi = psi(Alpha) - repmat(normTerm,1,obj.nScores);
                
%                 ElnPi_t = psi(Alpha_t) - psi(repmat(sum(Alpha_t,1),obj.nScores,1));
                ElnPiBundle = {ElnPi};
            catch e
                display(['psi error: ' e.message]);
            end
            
        end

        function [ET, pT] = expectedT(obj, C, lnP, lnPiBundle, nAssets)     
            
            if nargin < 6
                nAssets = length(obj.targets);
            end
            
            nonZeroScores = find(C{3}~=0);
            nValid = length(nonZeroScores);
            
            validDecs = C{3}(nonZeroScores); % c
            validN = C{2}(nonZeroScores); % index of data points

            indx = sub2ind([obj.nScores length(nonZeroScores)], ...
                            validDecs, ...
                            nonZeroScores);     
            lnPT = sparse(obj.nClasses, nAssets);
            
            lnPi = lnPiBundle{1};%Eta - log(1+exp(Eta));
            realIdxs = find(validN);
            for j=1:obj.nClasses                
                lnPT(j,:) = sparse(ones(1,nValid), validN', lnPi(j, indx), 1, nAssets);
                lnPT(j,realIdxs) = lnPT(j,realIdxs) + lnP(j);
            end
            
            rescale = 0;%repmat(-min(lnPT), obj.nClasses, 1);
            expA = exp(lnPT(:,realIdxs)+rescale);
            expB = repmat(sum(expA,1), obj.nClasses, 1);
            
            %stop any extreme values from causing Na
            expB(expA==Inf) = 1;
            expA(expA==Inf) = 1;
            
            pT = sparse(obj.nClasses, nAssets);
            pT(:, realIdxs) = expA./expB;
                        
            ET = pT;            
            if length(obj.targets)<1
                return
            end
            ET = obj.Tmat;
            ET(:, obj.testIdxs) = pT(:, obj.testIdxs);
            obj.combinedPost = ET;
%              ET(:, obj.targets~=0) = 0;
%              ET(sub2ind(size(ET), double(obj.targets(obj.targets~=0)), find(obj.targets~=0) )) = 1;
        end
        
        function combinedPost = combineCluster(obj, post, Tvec)   
            obj.setTargets(Tvec);       
            obj.nKnown = round(obj.nKnown);
            C = obj.prepareC(post);
            obj.initAlpha(length(C{1}));            
            [ET, nIt] = obj.combineScoreSet(C); 
            obj.combinedPost = ET;
            if obj.nClasses==2
                combinedPost(1, :) = ET(2, :);
            else
%                 [maxVals, maxIdx] = max(ET, [], 1);
                combinedPost = ET;%ET(sub2ind(size(ET), maxIdx, 1:length(maxIdx))) + maxIdx - 1;
            end

%             nItFile = sprintf('%s%s', obj.confSave, 'nIts_vb');
%             if exist(nItFile, 'file');
%                 prevNIts = dlmread(nItFile);
%                 prevNIts = [prevNIts nIt];
%             else
%                 prevNIts = nIt;
%             end
%             dlmwrite(nItFile, prevNIts);
            
            display([num2str(nIt) ' iterations for IBCCVB. sequential=' num2str(obj.sequential)]);
            
%             [classifierIds finalIdxs] = unique(C{1}, 'last');
%             finalAlpha = EAlpha(:,:,finalIdxs);
%             finalAlpha(:,:,classifierIds) = finalAlpha;
%             obj.Alpha = finalAlpha;
        end  
        
        function [combinedPost, agentRatings] = combineDecisions(obj, baseOutputs, ~) 
            % baseOutputs - a cell array with 3 cells; the first contains
            % an ordered vector of base classifier IDs; the second contains a vector
            % of object IDs for the objects to be classified; the third
            % contains the base classifier output scores. 
            % clusters - set to [] if not performing clustering
            if isempty(obj.Alpha)
                obj.Alpha = zeros(obj.nClasses, obj.nScores, length(baseOutputs{1}));                   
            elseif iscell(obj.Alpha)
                obj.Alpha = obj.Alpha{1};
                newSamples = length(baseOutputs{1}) - size(obj.Alpha,3);
                if newSamples>0
                    obj.Alpha = cat(3, obj.Alpha, zeros(obj.nClasses, obj.nScores, newSamples));
                    obj.Alpha_t = cat(2, obj.Alpha_t, zeros(obj.nScores, newSamples));
                end
            end
            
            %get the relevant inputs
            combinedPost = obj.combineCluster( baseOutputs, obj.targets);    
  
            agentRatings = obj.Alpha;            
        end        
        
        function initAlpha(obj, nDupes, Alpha)
            if isempty(obj.Alpha0)
                obj.Alpha0 = zeros(obj.nClasses, obj.nScores, nDupes);

                obj.Alpha0(:, :, :) = 1 ./ obj.nScores;      
                
                %sequential version needs stronger priors to avoid assuming too much from the early data points
                if obj.sequential
                    obj.Alpha0 = Alpha + 2;
                end
            else
                if size(obj.Alpha0, 3) < nDupes
                    obj.setAlphaPrior(obj.Alpha0, true, nDupes);
                end
            end             
        end       
            
        function [L, EEnergy, H] = lowerBound(obj, T, C, lnPiBundle, lnP, ~)

            nResponses = length(C{1});
            
            lnPi_t = lnPiBundle{2};
            
            idxs = sub2ind([obj.nScores nResponses], C{3}, (1:nResponses)');            
            ElnPC_t = lnPi_t(idxs);
            ElnPC = sum(ElnPC_t);
            
            if size(lnP, 1) > size(lnP, 2)
                lnP = lnP';
            end
            TargetCounts = sum(T, 2);            
            ElnPT = sum(TargetCounts .* lnP', 1);
        
            [AlphaPr_t AlphaPost_t] = obj.lnPiPrior(C, lnPiBundle{1}, T);
            ElnPPi_t = gammaln(sum(AlphaPr_t, 1))-sum(gammaln(AlphaPr_t),1) + sum((AlphaPr_t-1).*lnPi_t, 1);  
            ElnPPi = sum(ElnPPi_t);
            
            ElnPP = gammaln(sum(obj.Nu0, 2))-sum(gammaln(obj.Nu0),2) + sum((obj.Nu0-1).*lnP, 2);
            
            EEnergy = ElnPC + ElnPT + ElnPPi + ElnPP;
        
            if size(lnP, 1) > size(lnP, 2)
                lnP = lnP';
            end            
%             ElnQTMinusConst = sum(ElnPC_t) + sum(sum(T,2).*lnP');
%             
%             lnPi = Eta(:,idxs) - log(1+exp(Eta(:,idxs)));
%             Z = 0;
%             for j=1:obj.nClasses
%                 Z = Z + exp(lnPi(j,:) .* lnP(j));
%             end
%             ElnQT = ElnQTMinusConst - log(sum(Z))
            ElnQT = sum(sum(T(T~=0) .* log(T(T~=0))));
                                    
            ElnQPi_t = gammaln(sum(AlphaPost_t, 1))-sum(gammaln(AlphaPost_t),1) ...
                + sum((AlphaPost_t-1).*lnPi_t, 1);
            ElnQPi = sum(ElnQPi_t);

            PostNu = obj.Nu0 + TargetCounts';
            ElnQP = gammaln(sum(PostNu, 2))-sum(gammaln(PostNu),2) + sum((PostNu-1).*lnP, 2);
            
            H = - ElnQT - ElnQPi - ElnQP;
            
            L = EEnergy + H;
        end
        
        function printPiEvolution(obj, EPi, EAlpha, C)
                    
            EAlpha = EAlpha{1};
            
            classifiers = unique(C{1});
            for k=classifiers'
                display(['Pi for classifier ' num2str(k)]);
                kidxs = find(C{1}==k)';
                for n=[kidxs(1) kidxs(round(length(kidxs)/2)) kidxs(end)]
                    display([num2str(n) ',  ' num2str(C{3}(n)) ',  ' num2str(obj.targets(C{2}(n)))]);
                    EAlpha(:,:,n)
                end
            end            
        end        
    end 
end

