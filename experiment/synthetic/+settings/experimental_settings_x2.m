exp_settings.save_imgs = true

%data set sizes
exp_settings.training_set_size = 20;
exp_settings.test_data_size = 200;

exp_settings.length_history = 20;

%data generation
exp_settings.means = [-3 -5 -1 3 2; 3 5 1 -3 -2];

%test with sensors all of same quality
exp_settings.deviations = [1 2 1 3 1; 1 2 1 1 3];

exp_settings.p_c1 = 0.5;

exp_settings.noninf_means = 0;
exp_settings.noninf_dev = 5;

%sensors

%settings used: 
% inf =5 noninf = 11; max =10 min = 3
% inf = 3 noninf = 8
% inf = 2, noninf = 2; max = 3, min = 1
% inf = 1 noninf = 1

exp_settings.num_inf_sensors = 2;
exp_settings.num_noninf_sensors = 2;
exp_settings.num_sensors = num_inf_sensors + num_noninf_sensors;

exp_settings.p_switch = 0.015; % probability that a sensor will stop being useful

%agents and sensor allocation
exp_settings.num_agents = 5;

max_sensors = 3;
min_sensors = 1;

%number of clusters and clustering window length
sequence_length = 1;
K = 2;