### A Pluto.jl notebook ###
# v0.19.46

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ 63de9b5b-5e33-4b2c-99ac-9bfea2900f88
import Pkg; Pkg.activate(@__DIR__)

# ╔═╡ 020ebf16-6751-42c2-b438-fbc53e4b768e
using CairoMakie, LinearAlgebra, Colors, PlutoUI, Glob, FileIO, ArnoldiMethod, CacheVariables, Clustering, ProgressLogging, Dates, SparseArrays, Random, Logging, MAT

# ╔═╡ 86b2daa8-4ed6-4235-bbd0-a9d88a1a207e
html"""<style>
main {
    max-width: 66%;
    margin-left: 1%;
    margin-right: 2% !important;
}
"""

# ╔═╡ eab1b825-6441-4274-bb46-806c936d42a7
filepath = joinpath(@__DIR__, "MAT Files", "Salinas_corrected.mat")

# ╔═╡ bb44222b-68c3-4a8d-af9a-9aef2c0823e3
gt_filepath = joinpath(@__DIR__, "GT Files", "Salinas_gt.mat")

# ╔═╡ 431b7f3f-a3a0-4ea0-9df1-b80e1d7cc384
CACHEDIR = joinpath(@__DIR__, "cache_files", "Aerial Datasets")

# ╔═╡ 706e869c-e85b-420e-bb1e-6aa3f427cf1b
function cachet(@nospecialize(f), path)
	whenrun, timed_results = cache(path) do
		return now(), @timed f()
	end
	@info "Was run at $whenrun (runtime = $(timed_results.time) seconds)"
	timed_results.value
end

# ╔═╡ bf77d63c-09b5-4b80-aa8f-6a8a901a989a
vars = matread(filepath)

# ╔═╡ 7efc774a-eb75-44c5-95ee-76cb9b06f17a
vars_gt = matread(gt_filepath)

# ╔═╡ f60b11ba-3f17-4525-808c-82dd49fce5fe
data = vars["salinas_corrected"]

# ╔═╡ 278820b5-1037-4479-b79b-4e1d90c59f4d
gt_data = vars_gt["salinas_gt"]

# ╔═╡ f104e513-6bf3-43fd-bd87-a6085cf7eb21
gt_labels = sort(unique(gt_data))

# ╔═╡ c4456bce-09b5-4e11-8d1d-b16b50855281
bg_indices = findall(gt_data .== 0)

# ╔═╡ 48dc661e-86ca-4e65-8273-c34f518d0cc8
n_clusters = length(unique(gt_data)) - 1

# ╔═╡ 1000381a-3f79-46be-ab85-7ab94176d693
@bind band PlutoUI.Slider(1:size(data, 3), show_value=true)

# ╔═╡ 5763e16d-4f72-4302-99b7-c52b10269161
with_theme() do
	fig = Figure(; size=(600, 600))
	labels = length(unique(gt_data))
	colors = Makie.Colors.distinguishable_colors(n_clusters)
	ax = Axis(fig[1, 1], aspect=DataAspect(), yreversed=true)
	ax1 = Axis(fig[1, 2], aspect=DataAspect(), yreversed=true)
	image!(ax, permutedims(data[:, :, band]))
	hm = heatmap!(ax1, permutedims(gt_data); colormap=Makie.Categorical(colors))
	fig
end

# ╔═╡ 31eb6d55-a398-4715-a8fc-5780b0377e0d
begin
	mask = trues(size(data, 1), size(data, 2))
	for idx in bg_indices
		x, y = Tuple(idx)
		mask[x, y] = false
	end
end

# ╔═╡ c316e306-4260-48d5-b514-27bdc5509ae7
begin
function affinity(X::Matrix; max_nz=10, chunksize=isqrt(size(X,2)),
	func = c -> exp(-2*acos(clamp(c,-1,1))))

	# Compute normalized spectra (so that inner product = cosine of angle)
	X = mapslices(normalize, X; dims=1)

	# Find nonzero values (in chunks)
	C_buf = similar(X, size(X,2), chunksize)    # pairwise cosine buffer
	s_buf = Vector{Int}(undef, size(X,2))       # sorting buffer
	nz_list = @withprogress mapreduce(vcat, enumerate(Iterators.partition(1:size(X,2), chunksize))) do (chunk_idx, chunk)
		# Compute cosine angles (for chunk) and store in appropriate buffer
		C_chunk = length(chunk) == chunksize ? C_buf : similar(X, size(X,2), length(chunk))
		mul!(C_chunk, X', view(X, :, chunk))

		# Zero out all but `max_nz` largest values
		nzs = map(chunk, eachcol(C_chunk)) do col, c
			idx = partialsortperm!(s_buf, c, 1:max_nz; rev=true)
			collect(idx), fill(col, max_nz), func.(view(c,idx))
		end

		# Log progress and return
		@logprogress chunk_idx/cld(size(X,2),chunksize)
		return nzs
	end

	# Form and return sparse array
	rows = reduce(vcat, getindex.(nz_list, 1))
	cols = reduce(vcat, getindex.(nz_list, 2))
	vals = reduce(vcat, getindex.(nz_list, 3))
	return sparse([rows; cols],[cols; rows],[vals; vals])
end
affinity(cube::Array{<:Real,3}; kwargs...) =
	affinity(permutedims(reshape(cube, :, size(cube,3))); kwargs...)
end

# ╔═╡ f22664a1-bef4-4da4-9762-004aa54ed31d
permutedims(data[mask, :])

# ╔═╡ 56852fa7-8a0b-454b-ba70-ca12a86d551e
max_nz = 150

# ╔═╡ 5ced229a-cfd1-47e9-815e-69eb32b935bc
A = cachet(joinpath(CACHEDIR, "Affinity_Salinas_$max_nz.bson")) do
	affinity(permutedims(data[mask, :]); max_nz)
end

# ╔═╡ e87c036e-65b8-433e-8cdd-e2d119d8d458
function embedding(A, k; seed=0)
	# Set seed for reproducibility
	Random.seed!(seed)

	# Compute node degrees and form Laplacian
	d = vec(sum(A; dims=2))
	Dsqrinv = sqrt(inv(Diagonal(d)))
	L = Symmetric(I - (Dsqrinv * A) * Dsqrinv)

	# Compute eigenvectors
	decomp, history = partialschur(L; nev=k, which=:SR)
	@info history

	return mapslices(normalize, decomp.Q; dims=2)
end

# ╔═╡ 76e02728-ffa5-4214-9eb1-81e4e4779aca
V = embedding(A, n_clusters)

# ╔═╡ e7c650dd-8a82-44ac-a7f2-c14f0af3e1c7
function batchkmeans(X, k, args...; nruns=100, kwargs...)
	runs = @withprogress map(1:nruns) do idx
		# Run K-means
		Random.seed!(idx)  # set seed for reproducibility
		result = with_logger(NullLogger()) do
			kmeans(X, k, args...; kwargs...)
		end

		# Log progress and return result
		@logprogress idx/nruns
		return result
	end

	# Print how many converged
	nconverged = count(run -> run.converged, runs)
	@info "$nconverged/$nruns runs converged"

	# Return runs sorted best to worst
	return sort(runs; by=run->run.totalcost)
end

# ╔═╡ b0956a49-0ccc-43f5-a970-e1093b5930ce
spec_clusterings = batchkmeans(permutedims(V), n_clusters; maxiter=1000)

# ╔═╡ 01d90d35-fe22-45a5-9d34-48c55d16374e
aligned_assignments(clusterings, baseperm=1:maximum(first(clusterings).assignments)) = map(clusterings) do clustering
	# New labels determined by simple heuristic that aims to align different clusterings
	thresh! = a -> (a[a .< 0.2*sum(a)] .= 0; a)
	alignments = [thresh!(a) for a in eachrow(counts(clusterings[1], clustering))]
	new_labels = sortperm(alignments[baseperm]; rev=true)

	# Return assignments with new labels
	return [new_labels[l] for l in clustering.assignments]
end

# ╔═╡ 35d1546a-730c-4701-85b6-08d06adb68a4
spec_aligned = aligned_assignments(spec_clusterings)

# ╔═╡ 883cf099-8b07-4dac-8cde-ab0e8cd3a97f


# ╔═╡ 6cc95f84-a545-40f3-8ade-ecc3432c41c0
@bind spec_clustering_idx PlutoUI.Slider(1:length(spec_clusterings); show_value=true)

# ╔═╡ 3894966f-662e-4296-8c89-87cfe06eebab
# clu_map = fill(NaN32, size(data)[1:2])

# ╔═╡ 23f2afbf-7635-4827-9a8f-2dc1c98e2d8e
with_theme() do
	assignments, idx = spec_aligned, spec_clustering_idx

	# Create figure
	fig = Figure(; size=(800, 650))
	colors = Makie.Colors.distinguishable_colors(n_clusters)

	# Show data
	ax = Axis(fig[1,1]; aspect=DataAspect(), yreversed=true, title="Ground Truth")
	
	hm = heatmap!(ax, permutedims(gt_data); colormap=Makie.Categorical(colors))
	Colorbar(fig[2,1], hm, tellwidth=false, vertical=false, ticklabelsize=:8)

	# Show cluster map
	ax = Axis(fig[1,2]; aspect=DataAspect(), yreversed=true, title="Clustering Results")
	clustermap = fill(NaN32, size(data)[1:2])
	clustermap[mask] .= assignments[idx]
	hm = heatmap!(ax, permutedims(clustermap); colormap=Makie.Categorical(colors))
	Colorbar(fig[2,2], hm, tellwidth=false, vertical=false, ticklabelsize=:8)

	fig
end

# ╔═╡ 1c27672e-4216-453b-ab75-d8e19143ff12
md"""
### Confusion Matrix
"""

# ╔═╡ 8ae43452-1f71-4440-9b08-56d57a0f4424
ground_labels = filter(x -> x != 0, gt_labels)

# ╔═╡ a9646e81-b0e6-4b04-a191-3021309ebb78
true_labels = length(ground_labels)

# ╔═╡ 81932d2b-b075-43fa-af5e-3fbc2045774d
cluster_results = fill(NaN32, size(data)[1:2]);

# ╔═╡ 228c9083-0264-42a4-a47f-fe842c1ff850
assignments, idx = spec_aligned, spec_clustering_idx

# ╔═╡ fc0d44fe-062a-4af0-af6d-fcee7edca62d
cluster_results[mask] .= assignments[idx]

# ╔═╡ acd3c027-2283-4d66-9642-891caf332a01
predicted_labels = n_clusters

# ╔═╡ 31bfc63c-e722-414c-9253-6840be5c34ce
confusion_matrix = zeros(Float64, true_labels, predicted_labels);

# ╔═╡ 2ee36828-4c7b-4a9f-bae4-2d138cf96988
for (label_idx, label) in enumerate(ground_labels)
	
	label_indices = findall(gt_data .== label)

	cluster_values = [cluster_results[idx] for idx in label_indices]
	t_pixels = length(cluster_values)
	cluster_counts = [count(==(cluster), cluster_values) for cluster in 1:n_clusters]
	confusion_matrix[label_idx, :] .= [count / t_pixels * 100 for count in cluster_counts]
end

# ╔═╡ 4eedfb19-0fdd-4e5b-b2f5-ec38d5b2b03a
confusion_matrix

# ╔═╡ e1efb7a4-fa5e-478a-942d-4986cf0db9d2
with_theme() do
	assignments, idx = spec_aligned, spec_clustering_idx

	# Create figure
	fig = Figure(; size=(800, 550))
	colors = Makie.Colors.distinguishable_colors(n_clusters)

	# Show data
	ax = Axis(fig[1,1]; aspect=DataAspect(), yreversed=true, title="Ground Truth")
	
	hm = heatmap!(ax, permutedims(gt_data); colormap=Makie.Categorical(colors))
	Colorbar(fig[2,1], hm, tellwidth=false, vertical=false, ticklabelsize=:8)

	# Show cluster map
	ax = Axis(fig[1,2]; aspect=DataAspect(), yreversed=true, title="Clustering Results")
	clustermap = fill(NaN32, size(data)[1:2])
	clustermap[mask] .= assignments[idx]
	hm = heatmap!(ax, permutedims(clustermap); colormap=Makie.Categorical(colors))
	Colorbar(fig[2,2], hm, tellwidth=false, vertical=false, ticklabelsize=:8)

	fig
end

# ╔═╡ 75895597-36d7-4ab8-b4b7-2e1b2fb5cb01
with_theme() do
	fig = Figure(; size=(900, 800))
	ax = Axis(fig[1, 1], aspect=DataAspect(), yreversed=true, xlabel = "Predicted Labels", ylabel = "True Labels", xticks = 1:predicted_labels, yticks = 1:true_labels)
	hm = heatmap!(ax, confusion_matrix, colormap=:viridis)
	pm = permutedims(confusion_matrix)

	for i in 1:true_labels, j in 1:predicted_labels
        value = round(pm[i, j], digits=1)
        text!(ax, i - 0.02, j - 0.1, text = "$value", color=:white, align = (:center, :center), fontsize=14)
    end
	Colorbar(fig[1, 2], hm)
	fig
end

# ╔═╡ Cell order:
# ╟─86b2daa8-4ed6-4235-bbd0-a9d88a1a207e
# ╠═63de9b5b-5e33-4b2c-99ac-9bfea2900f88
# ╠═020ebf16-6751-42c2-b438-fbc53e4b768e
# ╠═eab1b825-6441-4274-bb46-806c936d42a7
# ╠═bb44222b-68c3-4a8d-af9a-9aef2c0823e3
# ╠═431b7f3f-a3a0-4ea0-9df1-b80e1d7cc384
# ╠═706e869c-e85b-420e-bb1e-6aa3f427cf1b
# ╠═bf77d63c-09b5-4b80-aa8f-6a8a901a989a
# ╠═7efc774a-eb75-44c5-95ee-76cb9b06f17a
# ╠═f60b11ba-3f17-4525-808c-82dd49fce5fe
# ╠═278820b5-1037-4479-b79b-4e1d90c59f4d
# ╠═f104e513-6bf3-43fd-bd87-a6085cf7eb21
# ╠═c4456bce-09b5-4e11-8d1d-b16b50855281
# ╠═48dc661e-86ca-4e65-8273-c34f518d0cc8
# ╠═1000381a-3f79-46be-ab85-7ab94176d693
# ╠═5763e16d-4f72-4302-99b7-c52b10269161
# ╠═31eb6d55-a398-4715-a8fc-5780b0377e0d
# ╠═c316e306-4260-48d5-b514-27bdc5509ae7
# ╠═f22664a1-bef4-4da4-9762-004aa54ed31d
# ╠═56852fa7-8a0b-454b-ba70-ca12a86d551e
# ╠═5ced229a-cfd1-47e9-815e-69eb32b935bc
# ╠═e87c036e-65b8-433e-8cdd-e2d119d8d458
# ╠═76e02728-ffa5-4214-9eb1-81e4e4779aca
# ╠═e7c650dd-8a82-44ac-a7f2-c14f0af3e1c7
# ╠═b0956a49-0ccc-43f5-a970-e1093b5930ce
# ╠═01d90d35-fe22-45a5-9d34-48c55d16374e
# ╠═35d1546a-730c-4701-85b6-08d06adb68a4
# ╠═883cf099-8b07-4dac-8cde-ab0e8cd3a97f
# ╠═6cc95f84-a545-40f3-8ade-ecc3432c41c0
# ╠═3894966f-662e-4296-8c89-87cfe06eebab
# ╟─23f2afbf-7635-4827-9a8f-2dc1c98e2d8e
# ╟─1c27672e-4216-453b-ab75-d8e19143ff12
# ╠═8ae43452-1f71-4440-9b08-56d57a0f4424
# ╠═a9646e81-b0e6-4b04-a191-3021309ebb78
# ╠═81932d2b-b075-43fa-af5e-3fbc2045774d
# ╠═228c9083-0264-42a4-a47f-fe842c1ff850
# ╠═fc0d44fe-062a-4af0-af6d-fcee7edca62d
# ╠═acd3c027-2283-4d66-9642-891caf332a01
# ╠═31bfc63c-e722-414c-9253-6840be5c34ce
# ╠═2ee36828-4c7b-4a9f-bae4-2d138cf96988
# ╠═4eedfb19-0fdd-4e5b-b2f5-ec38d5b2b03a
# ╟─e1efb7a4-fa5e-478a-942d-4986cf0db9d2
# ╠═75895597-36d7-4ab8-b4b7-2e1b2fb5cb01
