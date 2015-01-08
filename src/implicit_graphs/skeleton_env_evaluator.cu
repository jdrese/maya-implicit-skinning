/*
 Implicit skinning
 Copyright (C) 2013 Rodolphe Vaillant, Loic Barthe, Florian Cannezin,
 Gael Guennebaud, Marie Paule Cani, Damien Rohmer, Brian Wyvill,
 Olivier Gourmel

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License 3 as published by
 the Free Software Foundation.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see <http://www.gnu.org/licenses/>
 */

#include "skeleton_env_evaluator.hpp"
#include "blending_functions.hpp"
#include "ad_hoc_hand.hpp"


/**
 *  @namespace Blend_func
 *  @brief Holds the blending functions used to blend the skeleton's bones
 */
// =============================================================================
namespace Blend_func {
// =============================================================================

/// @brief Blending between cluster pairs  @see Skeleton_env
//typedef Op_test BlendP;
typedef Umax Pairs;
//typedef Uclean BlendP;
//typedef Circle_anim BlendP;
//typedef OMUCircle BlendP;
//typedef Ucircle BlendP;
//typedef Ifrom<Umax> BlendP; // Umin
//typedef BulgeFreeBlending Pairs;
//typedef BulgeInContact BlendP;

/// @brief blending between cluster's bones
/// The blending of bones that belongs to the same cluster
/// (i.e. bones that are on the same level in the hierarchy and has the same
/// parent)
/// @see Skeleton_env
//typedef Umax Cluster;
typedef BulgeFreeBlending Cluster;
//typedef Uclean BlendG;
//typedef Usum BlendG;

}// END BlendingFunc ===========================================================

#define USE_GRID_ // Not compatible with had_hoc hand !

__device__ static
float eval_cluster(Vec3_cu& gf_clus, const Point_cu& p, int size, Skeleton_env::DBone_id first_bone)
{
    gf_clus = Vec3_cu(0.f, 0.f, 0.f);

    // if(size == 0) return 0.f; // This should be guaranted by construction

    float f      = 0.f;
    float f_clus = 0.f;
    Vec3_cu gf;
    for(int i = 0; i < size; i++){
        f = fetch_and_eval_bone(first_bone+i, gf, p);
        f_clus = Blend_func::Cluster::fngf(gf_clus, f_clus, f, gf_clus, gf);
    }
    return f_clus;
}

__device__
float Skeleton_env::compute_potential(Skel_id skel_id, const Point_cu& p, Vec3_cu& gf)
{
    typedef Cluster_cu Clus;
    float f = 0.f;
    gf = Vec3_cu(1.f, 0.f, 0.f);

#ifndef USE_GRID_
    // Without space acceleration structure
    Cluster_id off_cid = fetch_blending_list_offset( skel_id );
    // Clusters contains at first a list of pairs with dynamic blending
    // each pair is blend to others with a max then the rest of the skeleton
    // is blended  with a max
    Clus clus = fetch_blending_list( off_cid );
#else
    // With a grid as acceleration structure
    Cluster_id off_cid = fetch_grid_blending_list_offset(skel_id, p.to_vector());
    if( !off_cid.is_valid() /*Means we are outside the skeleton bbox*/)
        return 0.f;
    Clus clus = fetch_grid_blending_list( off_cid );
#endif

    // In the first cluster we don't store the blending type and controller id
    const int nb_pairs      = clus.nb_pairs;
    const int nb_singletons = clus.nb_singletons;

    // Blend the pairs
    float fn[2];
    Vec3_cu gfn[2];
    int i( 0 );
    for(; i < nb_pairs; i++)
    {
        for(int j = 0; j < 2; j++){
            #ifndef USE_GRID_
            clus = fetch_blending_list( off_cid + i*2 + j );
            #else
            clus = fetch_grid_blending_list( off_cid + i*2 + j );
            #endif
            fn[j] = eval_cluster(gfn[j], p, clus.nb_bone, clus.first_bone);
        }
        // Blend the pair
        fn[0] = fetch_binop_and_blend(gfn[0],
                                      clus.blend_type, clus.ctrl_id,  off_cid + i*2,
                                      fn[0], fn[1], gfn[0], gfn[1]); // FIXME: This call should be specific to grid when enabled
        // Blend with the other pairs
        f =  Blend_func::Pairs::fngf(gf, f, fn[0], gf, gfn[0]);
    }

    // Blend singletons with max
    i *= 2;
    const int off = i + nb_singletons;
    for(; i < off; i++)
    {
        #ifndef USE_GRID_
        clus = fetch_blending_list( off_cid + i);
        #else
        clus = fetch_grid_blending_list( off_cid + i);
        #endif

        fn[0] = eval_cluster(gfn[0], p, clus.nb_bone, clus.first_bone);
        #ifndef ENABLE_ADHOC_HAND
        f =  Blend_func::Pairs::fngf(gf, f, fn[0], gf, gfn[0]);
        #else
        Cluster_id clus_id = off_cid + i;
        // Blend singletons according to the user defined op
        f = fetch_binop_and_blend(gf, clus.blend_type, clus.ctrl_id,  clus_id,
                                      f, fn[0], gf, gfn[0]);// FIXME: This call should be specific to grid when enabled
        #endif
    }

    return f;
}