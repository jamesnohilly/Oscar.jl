# Detinko, Flannery, O'Brien "Recognizing finite matrix groups over infinite
# fields", Section 4.2
# `min_char` is the minimal characteristic of the returned group
function _isomorphic_group_over_finite_field(matrices::Vector{<:MatrixElem{T}}; check::Bool = true, min_char::Int = 3) where T <: Union{ZZRingElem, QQFieldElem, AbsSimpleNumFieldElem}
   @assert !isempty(matrices)

   K = base_ring(matrices[1])
   n = nrows(matrices[1])
   if check
      # Check whether all matrices have the same base ring,
      # are square of the same size, and invertible.
      for mat in matrices
         @req K == base_ring(mat) "matrices are not over the same base ring"
         @req is_unit(det(mat)) "matrices must be invertible"
         @req size(mat) == (n, n) "matrices must be square of the same size"
      end
   end

   if K isa ZZRing
      K = QQ
   end

   Fq, matrices_Fq, OtoFq = good_reduction(matrices, min_char-1)

   G = matrix_group(Fq, n, matrices_Fq)
   N = order(G)
   if !is_divisible_by(Hecke._minkowski_multiple(K, n), N)
      error("Group is not finite")
   end

   G_to_fin_pres = GAPWrap.IsomorphismFpGroupByGenerators(G.X, GapObj(gens(G); recursive = true))
   F = GAPWrap.Range(G_to_fin_pres)
   rels = GAPWrap.RelatorsOfFpGroup(F)

   gens_and_invsF = [ g for g in GAPWrap.FreeGeneratorsOfFpGroup(F) ]
   append!(gens_and_invsF, [ inv(g) for g in GAPWrap.FreeGeneratorsOfFpGroup(F) ])
   matrices_and_invs = copy(matrices)
   append!(matrices_and_invs, [ inv(M) for M in matrices ])
   for i = 1:length(rels)
      M = GAP.Globals.MappedWord(rels[i], GapObj(gens_and_invsF), GapObj(matrices_and_invs))
      if !isone(M)
         error("Group is not finite")
      end
   end
   return G, G_to_fin_pres, F, OtoFq
end

function good_reduction(matrices::Vector{<:MatrixElem{T}}, p::Int = 2) where T <: Union{ZZRingElem, QQFieldElem, AbsSimpleNumFieldElem}
   while true
      p = next_prime(p)
      b, Fq, matrices_Fq, OtoFq = test_modulus(matrices, p)
      b && return Fq, matrices_Fq, OtoFq
   end
end

# Small helper function to make the reduction call uniform
function _reduce(M::MatrixElem{AbsSimpleNumFieldElem}, OtoFq)
  e = extend(OtoFq, Hecke.nf(domain(OtoFq)))
  return map_entries(e, M)
end

function _reduce(M::MatrixElem{QQFieldElem}, Fp)
  return map_entries(Fp, M)
end

function _isomorphic_group_over_finite_field(G::MatrixGroup{T}; min_char::Int = 3) where T <: Union{ZZRingElem, QQFieldElem, AbsSimpleNumFieldElem}

  if is_empty(gens(G))
    F2 = GF(2)
    Gp = matrix_group([ identity_matrix(F2, degree(G)) ])
    img = function(x)
      return one(Gp)
    end

    preimg = function(y)
      return one(G)
    end
    return Gp, MapFromFunc(G, Gp, img, preimg)
  end

  matrices = map(matrix, gens(G))

  Gp, GptoF, F, OtoFq = _isomorphic_group_over_finite_field(matrices, min_char = min_char)

  img = function(x)
    return Gp(_reduce(matrix(x), OtoFq))
  end

  gen = gens(G)

  preimg_bare = function(y)
    return GAP.Globals.MappedWord(GAPWrap.UnderlyingElement(GAPWrap.Image(GptoF, y)),
                                  GAPWrap.FreeGeneratorsOfFpGroup(F),
                                  GapObj(gen))
  end

  preimg = y -> preimg_bare(map_entries(_ring_iso(Gp), matrix(y)))

  has_order(Gp) && set_order(G, order(Gp))

  mp = MapFromFunc(G, Gp, img, preimg)

  # try to improve `GapObj(G)`
  Gap_G = GapObj(G)
  Gap_Gp = GapObj(Gp)
  if !GAP.Globals.HasNiceMonomorphism(Gap_G)
    risoG = _ring_iso(G)
    risoGp = _ring_iso(Gp)

    # map from Gap_G to Gap_Gp
    fun = x -> map_entries(risoGp, _reduce(preimage_matrix(risoG, x), OtoFq))

    # map from Gap_Gp to Gap_G
    invfun = x -> GapObj(preimg_bare(x))

    Gap_mp = GAP.Globals.GroupHomomorphismByFunction(Gap_G, Gap_Gp, fun, invfun)
    GAP.Globals.SetNiceMonomorphism(Gap_G, Gap_mp)
    GAP.Globals.SetIsHandledByNiceMonomorphism(Gap_G, true)
  end

  return Gp, mp
end

function isomorphic_group_over_finite_field(G::MatrixGroup{T}; min_char::Int = 3) where T <: Union{ZZRingElem, QQFieldElem, AbsSimpleNumFieldElem}
  val = get_attribute!(G, :isomorphic_group_over_fq) do
    return _isomorphic_group_over_finite_field(G, min_char = min_char)
  end::Tuple{MatrixGroup, MapFromFunc}
  if characteristic(base_ring(val[1])) >= min_char
    return val
  else
    return _isomorphic_group_over_finite_field(G, min_char = min_char)
  end
end

# Detinko, Flannery, O'Brien "Recognizing finite matrix  groups over infinite
# fields", Section 3.1 claims that any prime != 2 not dividing any denominator
# of the matrices and their inverses (!) works, i.e. the projection is either
# an isomorphism or, if it is not injective, then the group generated by
# matrices cannot be finite.
function test_modulus(matrices::Vector{<:MatrixElem{T}}, p::Int) where T <: Union{ZZRingElem, QQFieldElem}
   Fp = GF(p)
   matrices_Fp = Vector{AbstractAlgebra.MatElem{elem_type(Fp)}}(undef, length(matrices))
   if p == 2
      return false, Fp, matrices_Fp, Fp
   end

   for M in matrices
      for i = 1:nrows(M)
         for j = 1:ncols(M)
            if iszero(M[i, j])
               continue
            end

            if mod(denominator(M[i, j]), p) == 0
               return false, Fp, matrices_Fp, Fp
            end
         end
      end
   end
   # I don't want to invert everything in char 0, so I just check whether the
   # matrices are still invertible mod p.
   for i = 1:length(matrices)
      matrices_Fp[i] = map_entries(Fp, matrices[i])
      if rank(matrices_Fp[i]) != nrows(matrices_Fp[i])
         return false, Fp, matrices_Fp, Fp
      end
   end

   return true, Fp, matrices_Fp, Fp
end

# Detinko, Flannery, O'Brien "Recognizing finite matrix  groups over infinite
# fields", Section 3.2 claims that any prime != 2 not dividing the discriminant
# of the defining polynomial and not dividing any denominator of the matrices
# and their inverses (!) works, i.e. the projection is either
# an isomorphism or, if it is not injective, then the group generated by
# matrices cannot be finite.
function test_modulus(matrices::Vector{T}, p::Int) where T <: MatrixElem{AbsSimpleNumFieldElem}
   @assert length(matrices) != 0
   K = base_ring(matrices[1])
   matrices_Fq = Vector{FqMatrix}(undef, length(matrices))
   if p == 2
      return false, GF(p, cached = false), matrices_Fq, Hecke.NfOrdToFqMor()
   end
   O = EquationOrder(K)
   if mod(discriminant(O), p) == 0
      return false, GF(p, cached = false), matrices_Fq, Hecke.NfOrdToFqMor()
   end
   for M in matrices
      for i = 1:nrows(M)
         for j = 1:ncols(M)
            if iszero(M[i, j])
               continue
            end

            if mod(denominator(M[i, j]), p) == 0
               return false, GF(p, cached = false), matrices_Fq, Hecke.NfOrdToFqMor()
            end
         end
      end
   end

   # p is does not divide disc(O), so it's not an index divisor, so we don't
   # have to work in the maximal order here.
   P = prime_ideals_over(O, p)
   Fq, OtoFq = residue_field(O, P[1])
   matrices_Fq = Vector{dense_matrix_type(elem_type(Fq))}(undef, length(matrices))
   # I don't want to invert everything in char 0, so I just check whether the
   # matrices are still invertible mod p.
   for i = 1:length(matrices)
      matrices_Fq[i] = map_entries(a -> OtoFq(O(numerator(a)))//OtoFq(O(denominator(a))), matrices[i])
      if rank(matrices_Fq[i]) != nrows(matrices_Fq[i])
         return false, Fq, matrices_Fq, Hecke.NfOrdToFqMor()
      end
   end

   return true, Fq, matrices_Fq, OtoFq
end

# Return the largest possible order of a finite subgroup of GL(n, QQ) (equivalently:
# of GL(n, ZZ), as any finite subgroup of GL(n, QQ) is conjugate to a subgroup of GL(n, ZZ)).
# Always return a ZZRingElem, only the orders for n <= 16 would fit into an Int64.
#
# This relies on results in a preprint "The orders of finite linear groups" by
# W. Feit (1995), possibly published as mathscinet.ams.org/mathscinet-getitem?mr=1484185
# in the "Proceedings of the First Jamaican Conference on Group Theory and its
# Applications", 1996. However, it seems basically impossible to that paper.
# Geoff Robinson claims to have the preprint and posted the relevant information
# at mathoverflow.net/questions/168292/maximal-order-of-finite-subgroups-of-gln-z .
# The table is also repeated in [BDEPS04] where the authors however state that
# Feit does not actually provide a proof, and in any case relies heavily on unpublished
# work by Weisfeiler.
#
# Since this leaves the result in doubt, we do not currently actually use this code,
# and instead resort to the Minkowski bound and its generalization. Luckily for us,
# Hecke already implements these.
const max_ords = [ 2, 12, 48, 1152, 3840, 103680, 2903040, 696729600, 1393459200, 8360755200 ]
function largest_order_of_finite_linear_group_qq(n::Int)
   @assert n >= 0
   n <= 10 && return ZZRingElem(max_ords[n])
   # For n > 10, we can use 2^n*n!
   return factorial(ZZRingElem(n)) << n
end
