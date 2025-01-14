function amb = amt(ama)
%AMT Matrix array transpose.
%   Copyright (c) 2013,  Talal Rahman,  Jan Valdman
%
%   ama: [nx x ny x nz]
%
%   amb: [ny x nx x nz]

[nx, ny, nz] = size(ama);

row = (1:nx)';
row = row(:, ones(ny, 1));

col = 1:ny;
col = col(ones(nx, 1), :);

ind = row + (col - 1) * nx;
ind = ind';
ind = ind(:, :, ones(nz, 1));

off = 0:nx*ny:(nz-1)*nx*ny;
off = reshape(off(ones(nx * ny, 1), :), ny, nx, nz);

ind = ind + off;

amb = ama(ind);
