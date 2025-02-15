function lap_eig = compute_laplace_eig(femesh, pde, eiglim, neig_max)
%COMPUTE_LAPLACE_EIG Compute Laplace eigenvalues, functions and product moments.
%
%   femesh: struct
%   pde: struct
%   eiglim: [1 x 1]
%   neig_max: [1 x 1]
%
%   lap_eig: struct with fields
%       values: [neig x 1]
%       funcs: [npoint x neig]
%       moments: [neig x neig x 3]
%       massrelax: [neig x neig]
%       totaltime: [1 x 1]


% Measure computational time of eigendecomposition
starttime = tic;

% Solver parameters
params = {};
% params = [params {"Tolerance" 1e-12}];
params = [params {"Display" true}];

% Check if user has provided a requested number of eigenvalues
if nargin < nargin(@compute_laplace_eig)
    % Compute all eigenvalues
    neig_max = Inf;
end

% Extract domain parameters
diffusivity = pde.diffusivity;
relaxation = pde.relaxation;

% Sizes
ncompartment = femesh.ncompartment;

% Assemble finite element matrices
disp("Setting up FEM matrices");
M_cmpts = cell(1, ncompartment);
K_cmpts = cell(1, ncompartment);
R_cmpts = cell(1, ncompartment);
Jx_cmpts = repmat({cell(1, ncompartment)}, 1, 3);
for icmpt = 1:ncompartment
    % Finite elements
    points = femesh.points{icmpt};
    facets = femesh.facets(icmpt, :);
    elements = femesh.elements{icmpt};
    [~, volumes] = get_volume_mesh(points, elements);

    % Assemble mass, stiffness, and T2-relaxation matrices in compartment
    M_cmpts{icmpt} = mass_matrixP1_3D(elements', volumes');
    K_cmpts{icmpt} = stiffness_matrixP1_3D(elements', points', diffusivity(:, :, icmpt));
    R_cmpts{icmpt} = 1 / relaxation(icmpt) * M_cmpts{icmpt};
    
    % Assemble moment matrices (coordinate weighted mass matrices)
    for idim = 1:3
        Jx_cmpts{idim}{icmpt} = mass_matrixP1_3D(elements', volumes', points(idim, :)');
    end
end

% Create global mass, stiffness, relaxation, flux, and moment matrices (sparse)
disp("Coupling FEM matrices");
M = blkdiag(M_cmpts{:});
K = blkdiag(K_cmpts{:});
R = blkdiag(R_cmpts{:});
Jx = cellfun(@(J) blkdiag(J{:}), Jx_cmpts, "UniformOutput", false);
Q_blocks = assemble_flux_matrix(femesh.points, femesh.facets);
Q = couple_flux_matrix(femesh, pde, Q_blocks, false);

fprintf("Eigendecomposition of FE matrices: size %d x %d\n", size(M));

% % Solve explicit eigenvalue problem, computing all eigenvalues after
% % inverting the mass matrix
% tic
% [funcs, values] = eig(full(M \ (K + Q)));
% toc

% % Solve generalized eigenvalue problem, computing all eigenvalues
% tic
% [funcs, values] = eig(full(K + Q), full(M));
% toc

% Compute at most all eigenvalues in the given domain
neig_max = min(neig_max, size(M, 1));
% ssdim = 4 * neig_max;
% if ssdim < size(M, 1)
%     params = [params {"SubspaceDimension" ssdim}];
% end

% Solve generalized eigenproblem, computing the smallest eigenvalues only.
% If 2 * neig_max >= nnode, a full decomposition is performed,
% calling the eig function inside eigs
tic
[funcs, values] = eigs(K + Q, M, neig_max, "smallestreal", ...
    "IsSymmetricDefinite", true, params{:}); % "smallestabs"
toc

disp("Done with eigendecomposition");

% Order eigenvalues in increasing order
[values, indices] = sort(diag(values));
funcs = funcs(:, indices);

if any(values < 0)
    i = find(values < 0);
    i_str = sprintf(join(repmat("%d", 1, length(i))), i);
    v_str = sprintf(join(repmat("%g", 1, length(i))), values(i));
    warning("Found negative eigenvalues: indices " + i_str + ", values " + v_str + ". Setting them to zero.");
    values(i) = 0;
end

% Remove eigenvalues above interval defined by length scale
neig_all = length(values);
inds_keep = values <= eiglim;
values = values(inds_keep);
funcs = funcs(:, inds_keep);
neig = length(values);

% Check that the entire interval was explored
if neig == neig_all && ~isinf(eiglim)
    warning("No eigenvalues were outside the interval. Consider increasing neig_max " ...
        + "if there are more eigenvalues that may not have been found in the interval.");
end

fprintf("Found %d eigenvalues on [%g, %g]\n", neig, 0, eiglim);

% Normalize eigenfunctions with mass weighting
disp("Normalizing eigenfunctions");
funcs = funcs ./ sqrt(dot(funcs, M * funcs));

% Compute first order moments of of eigenfunction products
tic
disp("Computing first order moments of products of eigenfunction pairs");
moments = zeros(neig, neig, 3);
for idim = 1:3
    moments(:, :, idim) = funcs' * Jx{idim} * funcs;
end
disp("Computing T2-weighted Laplace mass matrix");
massrelax = funcs' * R * funcs;
toc

% Create output structure
lap_eig.values = values;
lap_eig.funcs = funcs;
lap_eig.moments = moments;
lap_eig.massrelax = massrelax;
lap_eig.totaltime = toc(starttime);

% Display function evaluation time
disp("Done with eigendecomposition.");
toc(starttime);
