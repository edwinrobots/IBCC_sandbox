function [P_class,P_feat_class,Alpha,Nu]=multi_classifier(X,T, Alpha0, Nu0)
%For binary features/classifier outputs only, i.e. responses that are either 0 or 1
% If other values are used (e.g. counts of features) these are treated as
% multiple occurrences of binary values, not as distinct categorical
% values.

nclasses = size(T,2);

if nargin < 4
    Nu0 = 1;
end

Nu = sum(T,1) + Nu0;
NuSum = sum(Nu);

P_class = Nu/NuSum;

P_feat_class = zeros(size(X,2),nclasses);

Alpha = zeros(nclasses, 2, size(X,2));

for c = 1 : nclasses,
    inds = find(T(:,c)==1);
    
    count = sum(X(inds,:),1);
    nPos = sum(X(inds,:)>0,1);
    nNegs = length(inds) - nPos;
    
    if nargin < 3
        alpha = count + 1;
        alphaSum = count + nNegs + 2;
    else
        alpha = count + Alpha0(c, 1);
        alphaSum = count + nNegs + sum(Alpha0(c,:));
    end   

    Alpha(c,2,:) = alpha;
    Alpha(c,1,:) = alphaSum - alpha;
    
    P_feat_class(:,c) = alpha./alphaSum;
end

%filter common words - don't use their sample probabilities
% commonWords = find(sum( Alpha(:,2,:)>(15+Alpha0(2,1)), 1)==nclasses);% & sum( Alpha(:,2,:),1 )>20 );
% length(commonWords)
% P_feat_class(commonWords, :) = 1/nclasses;

