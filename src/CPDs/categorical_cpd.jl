#=
A categorical distribution

    Is compatible with Categorical

    P(x|parents(x)) ∈ Categorical

    Assumes the target and all parents are discrete integers 1:Nᵢ
=#

type CategoricalCPD <: CPDForm

    # data only initialized if has parents
    parental_assignments::Vector{Int} # preallocated array of parental assignments, in BN topological order
    parent_instantiation_counts::Tuple{Vararg{Int}} # list of integer instantiation counts, in BN topological order
    probabilities::Matrix{Float64} # n_instantiations × nparental_instantiations of parents

    CategoricalCPD() = new()
    function CategoricalCPD(
        parental_assignments::Vector{Int},
        parent_instantiation_counts::Tuple{Vararg{Int}},
        probabilities::Matrix{Float64},
        )
        new(parental_assignments, parent_instantiation_counts, probabilities)
    end
end

function condition!{D<:Categorical,C<:CategoricalCPD}(cpd::CPD{D,C}, a::Assignment)

    if !parentless(cpd)

        form = cpd.form

        # pull the parental assignments
        for (i,p) in enumerate(cpd.parents)
            form.parental_assignments[i] = a[p]
        end

        # get the parental assignment index
        j = sub2ind_vec(form.parent_instantiation_counts, form.parental_assignments)

        # build the distribution
        p = cpd.d.p
        for i in 1 : length(p)
            p[i] = form.probabilities[i,j]
        end
    end

    cpd.d
end

function Distributions.fit{D<:Categorical,C<:CategoricalCPD}(
    ::Type{CPD{D,C}},
    data::DataFrame,
    target::NodeName;
    dirichlet_prior::Float64=0.0, # prior counts
    )

    # no parents

    arr = data[target]
    eltype(arr) <: Int || error("fit CategoricalCPD requrires target to be an integer")

    n_instantiations = infer_number_of_instantiations(arr)

    probabilities = fill(dirichlet_prior, n_instantiations)
    for v in data[target]
        probabilities[v] += 1.0
    end
    probabilities ./= nrow(data)

    CPD(target, Categorical(probabilities), CategoricalCPD())
end
function Distributions.fit{D<:Categorical,C<:CategoricalCPD}(
    ::Type{CPD{D,C}},
    data::DataFrame,
    target::NodeName,
    parents::Vector{NodeName};
    dirichlet_prior::Float64=0.0, # prior counts
    )

    # with parents

    if isempty(parents)
        return fit(CPD{D,C}, data, target, dirichlet_prior=dirichlet_prior)
    end

    # ---------------------
    # pull discrete dataset
    # 1st row is all of the data for the 1st parent
    # 2nd row is all of the data for the 2nd parent, etc.
    # calc parent_instantiation_counts

    nparents = length(parents)
    discrete_data = Array(Int, nparents, nrow(data))
    parent_instantiation_counts = Array(Int, nparents)
    for (i,p) in enumerate(parents)
        arr = data[p]
        parent_instantiation_counts[i] = infer_number_of_instantiations(arr)

        for j in 1 : nrow(data)
            discrete_data[i,j] = arr[j]
        end
    end

    # ---------------------
    # pull sufficient statistics

    q = prod(parent_instantiation_counts)
    stridevec = fill(1, nparents)
    for k = 2 : nparents
        stridevec[k] = stridevec[k-1] * parent_instantiation_counts[k-1]
    end
    js = (discrete_data - 1)' * stridevec + 1

    target_data = convert(Vector{Int}, data[target])
    n_instantiations = infer_number_of_instantiations(target_data)

    probs = full(sparse(target_data, vec(js), 1.0, n_instantiations, q)) # currently a set of counts
    probs = probs + dirichlet_prior

    for i in 1 : q
        tot = sum(probs[:,i])
        if tot > 0.0
            probs[:,i] ./= tot
        else
            probs[:,i] = 1.0/n_instantiations
        end
    end

    probabilities = probs
    parental_assignments = Array(Int, nparents)
    parent_instantiation_counts = tuple(parent_instantiation_counts...)

    form = CategoricalCPD(parental_assignments, parent_instantiation_counts, probabilities)
    CPD(target, parents, Categorical(n_instantiations), form)
end

