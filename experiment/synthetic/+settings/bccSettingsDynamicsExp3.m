
%bcc multiple test settings: easy tests

expSettings = settings.ExpSettings('/homes/49/edwin/matlab/combination/data/dynamicVB/bccDynamicsExp3_buggerations');

expSettings.spreadTargets = true;

%Ibcc
expSettings.propKnown = [0.2];%[0 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45];
%expSettings.propKnown = 0;
%expSettings.propKnown = [0 0.1 0.4];
%expSettings.propKnown = [0 0.1 0.25 0.4];

expSettings.iPropKnown = 1;

% expSettings.lambdaSym = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9];
% expSettings.iLambdaSym = 1;
% 
% expSettings.lambdaMag = [1 10 50 100];
% expSettings.iLambdaMag = 1;

%detailed runs use these settings
%propKnown = [0 0.005 0.01 0.02 0.04 0.06 0.08 0.1 0.2];
%lambdaSym = [0.5, 0.6, 0.7, 0.8, 0.9];
%lambdaMag = [0.1 0.5 1 5];

expSettings.nDatasets = 10;
expSettings.nRepeats = 1;

expSettings.nSamples = 500;

expSettings.initCombinedPosteriors();

%cluster agents over a data sequence of 20. use posteriors as cluster input
%data.
expSettings.clusterData = 'post';
expSettings.weightClusterInput = false;
expSettings.topSaveDir = '/homes/49/edwin/matlab/combination/data/dynamicVB/bccDynamicsExp3_arses';
expSettings.noOverwriteData = true;
%expSettings.expLabel = 'dlrCombiners'; %experiment label
expSettings.expLabel = 'comparison';

%other more boring things
expSettings.saveImgs = true;
expSettings.agentType='dlr';

%data set sizes
expSettings.nTrainingSamples = 0;
expSettings.lengthHistory = 50;

%data generation
expSettings.means = [-3 -2 -1; 3 2 1]; %[-3 -4 -5 -9 8; 3 4 5 9 -8];

%test with sensors all of same quality
expSettings.deviations = [1 2 1 ; 1 1 2];

expSettings.p_c1 = 0.5;

expSettings.noninfMean = 0;
expSettings.noninfDev = 5;

%sensors

%settings used: 
% inf =5 noninf = 11; max =10 min = 3
% inf = 3 noninf = 8
% inf = 2, noninf = 2; max = 3, min = 1
% inf = 1 noninf = 1

expSettings.nInfSensors = 4;
expSettings.nNoninfSensors = 16;%36; %IBCC-vB dies when we have > 33 uninf agents!

expSettings.pSwitch = 0.0; % probability that a sensor will stop being useful
expSettings.definiteSwitch = [0.07 0.08 0.09 0.10 ...
    0.13 0.14 0.15 0.16...
    0.27 0.28 0.29 0.30...
    0.33 0.34 0.35 0.36...
    0.47 0.48 0.49 0.50...
    0.53 0.54 0.55 0.56...
    0.67 0.68 0.69 0.70...
    0.73 0.74 0.75 0.76...
    0.87 0.88 0.89 0.90...
    0.93 0.94 0.95 0.96];%[0.03 0.06 0.13 0.16 0.22 0.25 0.32 0.35 0.44 0.47 0.54 0.57 0.63 0.67 0.73 0.77 0.83 0.87 0.93 0.97];%[0.12 0.28 0.44 0.56 0.68 0.8];%
expSettings.pMissing = 0.00;
expSettings.pCorrupt = 0.0;
expSettings.pFlipLabel = 0.0;
expSettings.pFlipSensor = 0.0;

%agents and sensor allocation
expSettings.nAgents = 20;
expSettings.nInformedAgents = 4;

expSettings.maxSensors = 1;
expSettings.minSensors = 1;

%number of clusters and clustering window length
expSettings.seqLength = 20;
expSettings.K = 2;