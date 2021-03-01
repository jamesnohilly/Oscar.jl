
import Markdown
import Base: ==

export Cone,
    PolyhedralFan,
    Polyhedron,
    IncidenceMatrix,
    ambient_dim,
    codim,
    convex_hull,
    cube,
    dim,
    facets,
    facets_as_halfspace_matrix_pair,
    face_fan,
    feasible_region,
    iscomplete,
    isregular,
    issmooth,
    lineality_space,
    LinearProgram,
    maximal_cones,
    maximal_cones_as_incidence_matrix,
    maximal_value,
    maximal_vertex,
    minimal_value,
    minimal_vertex,
    newton_polytope,
    normalized_volume,
    normal_fan,
    n_facets,
    n_maximal_cones,
    n_rays,
    n_vertices,
    objective_function,
    recession_cone,
    solve_lp,
    support_function,
    pm_polytope,
    positive_hull,
    rays,
    vertices,
    visual,
    volume

include("helpers.jl")
include("Polyhedron.jl")
include("Cone.jl")
include("LinearProgram.jl")
include("PolyhedralFan.jl")
