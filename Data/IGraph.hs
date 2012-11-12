-- | Haskell bindings to the igraph C library.
--
-- See <http://igraph.sourceforge.net/doc/html/index.html> in the specified
-- section for more documentation about a specific function.
module Data.IGraph
  ( -- * Base types
    Graph (..), E (..)
  , D, U, IsUnweighted
  , Weighted, toEdgeWeighted, getWeight
  , IsUndirected, IsDirected

    -- * Construction / modification
  , emptyGraph
  , fromList, fromListWeighted
  , insertEdge
  , deleteEdge
  , deleteNode
  , reverseGraphDirection
  , toDirected, toUndirected
    -- * Query
  , numberOfNodes
  , numberOfEdges
  , member
  , nodes
  , edges
  , neighbours

    -- * Chapter 11. Vertex and Edge Selectors and Sequences, Iterators

    -- ** 11\.2 Vertex selector constructors
  , VertexSelector(..) --, NeiMode(..)

    -- ** 11\.3 Generic vertex selector operations
  , vsSize, selectedVertices

    -- ** 11\.6 Edge selector constructors
  , EdgeSelector(..)

    -- ** 11\.8 Generic edge selector operations
  , esSize, selectedEdges

    -- * Chapter 13\. Structural Properties of Graphs

    -- ** 13\.1 Basic properties
  , areConnected

    -- ** 13\.2 Shortest Path Related Functions
  , shortestPaths,       shortestPathsDijkstra, shortestPathsBellmanFord, shortestPathsJohnson
  , getShortestPaths,    getShortestPathsDijkstra
  , getShortestPath,     getShortestPathDijkstra
  , getAllShortestPaths, getAllShortestPathsDijkstra
  , averagePathLength
  , pathLengthHist
  , diameter, diameterDijkstra
  , girth
  , eccentricity
  , radius

    -- ** 13\.4 Graph Components
  , subcomponent
  -- , subgraph
  , isConnected
  -- , decompose
  , Connectedness(..)
  , articulationPoints

    -- ** 13\.5 Centrality Measures
  , closeness
  , betweenness, edgeBetweenness
    --pagerank stuff here
  , constraint
  , maxdegree
  , strength

    -- ** 13\.6 Estimating Centrality Measures
  , closenessEstimate
  , betweennessEstimate
  , edgeBetweennessEstimate

    -- ** 13\.7 Centralization
  , centralizationDegree
  , centralizationBetweenness
  , centralizationCloseness
  , centralizationDegreeTMax
  , centralizationBetweennessTMax
  , centralizationClosenessTMax

    -- ** 13\.8 Similarity Measures
  , bibCoupling
  , cocitation
  , similarityJaccard
  , similarityJaccardPairs
  , similarityJaccardEs
  , similarityDice
  , similarityDicePairs
  , similarityDiceEs
  , similarityInverseLogWeighted

    -- ** 13\.9 Spanning Tress
  , minimumSpanningTree

    -- ** 13\.10 Transitivity or Clustering Coefficient
  , transitivityUndirected
  , transitivityLocalUndirected
  , transitivityAvglocalUndirected
  , transitivityBarrat

    -- ** 13\.12 Spectral properties
  , laplacian

    -- ** 13\.14 Mixing patterns
  , assortativityNominal
  , assortativity
  , assortativityDegree

    -- ** 13\.15 K-Cores
  , coreness

    -- ** 13\.16 Topological sorting, directed acyclic graphs
  , isDAG
  , topologicalSorting
  , FASAlgorithm(..)
  , feedbackArcSet

    -- ** 13\.17 Maximum cardinality search, graph decomposition, chordal graphs
  , maximumCardinalitySearch
  , isChordal
  ) where

import Data.IGraph.Internal
import Data.IGraph.Internal.Constants
import Data.IGraph.Types

import Data.Hashable
import Data.Map (Map)
import qualified Data.Map as M
import qualified Data.Foldable as F
import Data.List (nub)

import Foreign hiding (unsafePerformIO)
import Foreign.C
import System.IO.Unsafe (unsafePerformIO)


--------------------------------------------------------------------------------
-- 11.2 Vertex selector constructors

{- nothing here -}

--------------------------------------------------------------------------------
-- 11.3. Generic vertex selector operations

foreign import ccall "igraph_vs_size"
  c_igraph_vs_size :: GraphPtr -> VsPtr -> Ptr CInt -> IO CInt

vsSize :: Graph d a -> VertexSelector a -> Int
vsSize g vs = unsafePerformIO $ alloca $ \ip -> do
  _e <- withGraph g $ \gp ->
        withVs vs g $ \vsp ->
          c_igraph_vs_size gp vsp ip
  fromIntegral `fmap` peek ip 

foreign import ccall "selected_vertices"
  c_selected_vertices :: GraphPtr -> VsPtr -> VectorPtr -> IO Int

selectedVertices :: Graph d a -> VertexSelector a -> [a]
selectedVertices g vs = unsafePerformIO $ do
  let s = vsSize g vs
  v <- newVector s
  _ <- withGraph g  $ \gp  ->
       withVs vs g  $ \vsp ->
       withVector v $ \vp  ->
        c_selected_vertices gp vsp vp
  l <- vectorToList v
  return (map (idToNode'' g . round) l)

--------------------------------------------------------------------------------
-- 11.8. Generic edge selector operations

foreign import ccall "igraph_es_size"
  c_igraph_es_size :: GraphPtr -> EsPtr -> Ptr CInt -> IO CInt

esSize :: Graph d a -> EdgeSelector d a -> Int
esSize g es = unsafePerformIO $ alloca $ \ip -> do
  _e <- withGraph g $ \gp ->
        withEs es g $ \esp ->
          c_igraph_es_size
            gp
            esp
            ip
  fromIntegral `fmap` peek ip


foreign import ccall "selected_edges"
  c_selected_edges :: GraphPtr -> EsPtr -> VectorPtr -> IO CInt

selectedEdges :: Graph d a -> EdgeSelector d a -> [Edge d a]
selectedEdges g es = unsafePerformIO $ do
  let s = esSize g es
  v  <- newVector s
  _e <- withGraph g $ \gp ->
        withEs es g $ \esp ->
        withVector v $ \vp ->
          c_selected_edges
            gp
            esp
            vp
  l <- vectorToList v
  return $ map (edgeIdToEdge g . round) l

--------------------------------------------------------------------------------
-- 13.1 Basic properties

foreign import ccall "igraph_are_connected"
  c_igraph_are_connected :: GraphPtr -> CInt -> CInt -> Ptr CInt -> IO CInt

-- | 1\.1\. igraph_are_connected — Decides whether two vertices are connected
areConnected :: Graph d a -> a -> a -> Bool
areConnected g n1 n2 = case (nodeToId g n1, nodeToId g n2) of
  (Just i1, Just i2) -> unsafePerformIO $ withGraph g $ \gp -> alloca $ \bp -> do
     _ <- c_igraph_are_connected gp (fromIntegral i1) (fromIntegral i2) bp
     fmap (== 1) (peek bp)
  _ -> False

--------------------------------------------------------------------------------
-- 13.2 Shortest Path Related Functions

foreign import ccall "shortest_paths"
  c_igraph_shortest_paths :: GraphPtr -> MatrixPtr -> VsPtr -> VsPtr -> CInt -> IO CInt

-- | 2\.1\. igraph_shortest_paths — The length of the shortest paths between
-- vertices.
shortestPaths :: (Ord a, Hashable a)
              => Graph d a
              -> VertexSelector a
              -> VertexSelector a
              -> Map (a,a) (Maybe Int)
shortestPaths g vf vt =
  let ls = unsafePerformIO $ do
             ma <- newMatrix 0 0
             _e <- withGraph g $ \gp ->
                   withMatrix ma $ \mp ->
                   withVs vf g $ \vfp ->
                   withVs vt g $ \vtp ->
                     c_igraph_shortest_paths
                       gp
                       mp
                       vfp
                       vtp
                       (getNeiMode g)
             matrixToList ma
      nf = selectedVertices g vf
      nt = selectedVertices g vt
  in  M.fromList [ ((f,t), len)
                 | (f,lf)  <- zip nf ls
                 , (t,len) <- zip nt (map roundMaybe lf)
                 ]

roundMaybe :: Double -> Maybe Int
roundMaybe d = if d == 1/0 then Nothing else Just (round d)

foreign import ccall "shortest_paths_dijkstra"
  c_igraph_shortest_paths_dijkstra :: GraphPtr -> MatrixPtr -> VsPtr -> VsPtr
                                   -> VectorPtr -> CInt -> IO CInt

-- | 2\.2\. igraph_shortest_paths_dijkstra — Weighted shortest paths from some
-- sources.
shortestPathsDijkstra :: (Ord a, Hashable a)
                      => Graph (Weighted d) a
                      -> VertexSelector a
                      -> VertexSelector a
                      -> Map (a,a) (Maybe Int)
shortestPathsDijkstra g vf vt =
  let ls = unsafePerformIO $ do
             ma <- newMatrix 0 0
             _e <- withGraph g $ \gp ->
                   withWeights g $ \wp ->
                   withMatrix ma $ \mp ->
                   withVs vf g $ \vfp ->
                   withVs vt g $ \vtp ->
                     c_igraph_shortest_paths_dijkstra
                       gp
                       mp
                       vfp
                       vtp
                       wp
                       (getNeiMode g)
             matrixToList ma
      nf = selectedVertices g vf
      nt = selectedVertices g vt
  in  M.fromList [ ((f,t), len)
                 | (f,lf)  <- zip nf ls
                 , (t,len) <- zip nt (map roundMaybe lf)
                 ]

foreign import ccall "shortest_paths_bellman_ford"
  c_igraph_shortest_paths_bellman_ford :: GraphPtr -> MatrixPtr -> VsPtr -> VsPtr -> VectorPtr
                                       -> CInt -> IO CInt

-- | 2\.3\. igraph_shortest_paths_bellman_ford — Weighted shortest paths from some
-- sources allowing negative weights.
shortestPathsBellmanFord :: (Ord a, Hashable a)
                         => Graph (Weighted d) a
                         -> VertexSelector a
                         -> VertexSelector a
                         -> Map (a,a) (Maybe Int)
shortestPathsBellmanFord g vf vt =
  let ls = unsafePerformIO $ do
             ma <- newMatrix 0 0
             _e <- withGraph g $ \gp ->
                   withWeights g $ \wp ->
                   withMatrix ma $ \mp ->
                   withVs vf g $ \vfp ->
                   withVs vt g $ \vtp ->
                     c_igraph_shortest_paths_bellman_ford
                       gp
                       mp
                       vfp
                       vtp
                       wp
                       (getNeiMode g)
             matrixToList ma
      nf = selectedVertices g vf
      nt = selectedVertices g vt
  in  M.fromList [ ((f,t), len)
                 | (f,lf)  <- zip nf ls
                 , (t,len) <- zip nt (map roundMaybe lf)
                 ]

foreign import ccall "shortest_paths_johnson"
  c_igraph_shortest_paths_johnson :: GraphPtr -> MatrixPtr -> VsPtr -> VsPtr -> VectorPtr
                                  -> IO CInt

-- | 2\.4\. igraph_shortest_paths_johnson — Calculate shortest paths from some
-- sources using Johnson's algorithm.
shortestPathsJohnson :: (Ord a, Hashable a)
                     => Graph (Weighted d) a
                     -> VertexSelector a
                     -> VertexSelector a
                     -> Map (a,a) (Maybe Int)
shortestPathsJohnson g vf vt =
  let ls = unsafePerformIO $ do
             ma <- newMatrix 0 0
             _e <- withGraph g $ \gp ->
                   withWeights g $ \wp ->
                   withMatrix ma $ \mp ->
                   withVs vf g $ \vfp ->
                   withVs vt g $ \vtp ->
                     c_igraph_shortest_paths_johnson
                       gp
                       mp
                       vfp
                       vtp
                       wp
             matrixToList ma
      nf = selectedVertices g vf
      nt = selectedVertices g vt
  in  M.fromList [ ((f,t), len)
                 | (f,lf)  <- zip nf ls
                 , (t,len) <- zip nt (map roundMaybe lf)
                 ]

foreign import ccall "get_shortest_paths"
  c_igraph_get_shortest_paths :: GraphPtr -> VectorPtrPtr -> VectorPtrPtr -> CInt -> VsPtr -> CInt -> IO CInt

-- | 2\.5\. igraph_get_shortest_paths — Calculates the shortest paths from/to one
-- vertex.
getShortestPaths :: Graph d a
                 -> a                     -- ^ from
                 -> VertexSelector a      -- ^ to
                 -> [ ([a],[Edge d a]) ]  -- ^ list of @(vertices, edges)@
getShortestPaths g f vt =
  let mfi = nodeToId g f
   in case mfi of
           Nothing -> error "getShortestPaths: Invalid node"
           Just fi -> unsafePerformIO $ do
             vpv <- newVectorPtr 0
             vpe <- newVectorPtr 0
             _e  <- withGraph g $ \gp ->
                      withVectorPtr vpv $ \vpvp ->
                      withVectorPtr vpe $ \vpep ->
                      withVs vt g $ \vtp ->
                       c_igraph_get_shortest_paths
                         gp
                         vpvp
                         vpep
                         (fromIntegral fi)
                         vtp
                         (getNeiMode g)
             v <- vectorPtrToVertices g vpv
             e <- vectorPtrToEdges    g vpe
             return $ zip v e

foreign import ccall "igraph_get_shortest_path"
  c_igraph_get_shortest_path :: GraphPtr -> VectorPtr -> VectorPtr -> CInt -> CInt -> CInt -> IO CInt

-- | 2\.6\. igraph_get_shortest_path — Shortest path from one vertex to another
-- one.
getShortestPath :: Graph d a -> a -> a -> ([a],[Edge d a])
getShortestPath g n1 n2 =
  let mi1 = nodeToId g n1
      mi2 = nodeToId g n2
  in  case (mi1, mi2) of
           (Just i1, Just i2) -> unsafePerformIO $
             withGraph g $ \gp -> do
               v1 <- listToVector ([] :: [Int])
               v2 <- listToVector ([] :: [Int])
               e <- withVector v1 $ \vp1 -> withVector v2 $ \vp2 ->
                     c_igraph_get_shortest_path
                       gp
                       vp1
                       vp2
                       (fromIntegral i1)
                       (fromIntegral i2)
                       (getNeiMode g)
               if e == 0 then do
                   vert <- vectorToVertices g v1
                   edgs <- vectorToEdges    g v2
                   return ( vert, edgs )
                 else
                   error $ "getShortestPath: igraph error " ++ show e
           _ -> error "getShortestPath: Invalid nodes"

foreign import ccall "get_shortest_paths_dijkstra"
  c_igraph_get_shortest_paths_dijkstra :: GraphPtr -> VectorPtrPtr -> VectorPtrPtr
                                       -> CInt -> VsPtr -> VectorPtr -> CInt -> IO CInt

-- | 2\.7\. igraph_get_shortest_paths_dijkstra — Calculates the weighted
-- shortest paths from/to one vertex.
getShortestPathsDijkstra :: Graph (Weighted d) a
                         -> a                     -- ^ from
                         -> VertexSelector a      -- ^ to
                         -> [ ([a],[Edge (Weighted d) a]) ]  -- ^ list of @(vertices, edges)@
getShortestPathsDijkstra g f vt =
  let mfi = nodeToId g f
   in case mfi of
           Nothing -> error "getShortestPathsDijkstra: Invalid node"
           Just fi -> unsafePerformIO $ do
             vpv <- newVectorPtr 0
             vpe <- newVectorPtr 0
             _e  <- withGraph g $ \gp ->
                    withWeights g $ \wp ->
                    withVectorPtr vpv $ \vpvp ->
                    withVectorPtr vpe $ \vpep ->
                    withVs vt g $ \vtp ->
                     c_igraph_get_shortest_paths_dijkstra
                       gp
                       vpvp
                       vpep
                       (fromIntegral fi)
                       vtp
                       wp
                       (getNeiMode g)
             v <- vectorPtrToVertices g vpv
             e <- vectorPtrToEdges    g vpe
             return $ zip v e

foreign import ccall "igraph_get_shortest_path_dijkstra"
  c_igraph_get_shortest_path_dijkstra :: GraphPtr -> VectorPtr -> VectorPtr -> CInt
                                      -> CInt -> VectorPtr -> CInt -> IO CInt

-- | 2\.8\. igraph_get_shortest_path_dijkstra — Weighted shortest path from one
-- vertex to another one.
getShortestPathDijkstra :: Graph (Weighted d) a -> a -> a -> ([a],[Edge (Weighted d) a])
getShortestPathDijkstra g n1 n2 =
  let mi1 = nodeToId g n1
      mi2 = nodeToId g n2
  in  case (mi1, mi2) of
           (Just i1, Just i2) -> unsafePerformIO $ do
             v1 <- newVector 0
             v2 <- newVector 0
             e  <- withGraph g $ \gp ->
                   withWeights g $ \wp ->
                   withVector v1 $ \vp1 ->
                   withVector v2 $ \vp2 ->
                     c_igraph_get_shortest_path_dijkstra
                       gp
                       vp1
                       vp2
                       (fromIntegral i1)
                       (fromIntegral i2)
                       wp
                       (getNeiMode g)
             if e == 0 then do
                vert <- vectorToVertices g v1
                edgs <- vectorToEdges    g v2
                return ( vert, edgs )
              else
                error $ "getShortestPathDijkstra: igraph error " ++ show e
           _ -> error "getShortestPathDijkstra: Invalid nodes"

foreign import ccall "get_all_shortest_paths"
  c_igraph_get_all_shortest_paths :: GraphPtr
                                  -> VectorPtrPtr
                                  -> VectorPtr
                                  -> CInt
                                  -> VsPtr
                                  -> CInt
                                  -> IO CInt

-- | 2\.9\. igraph_get_all_shortest_paths — Finds all shortest paths (geodesics)
-- from a vertex to all other vertices.
getAllShortestPaths :: Graph d a
                    -> a                  -- ^ from
                    -> VertexSelector a   -- ^ to
                    -> [[a]]  -- ^ list of vertices along the shortest path from
                              -- @from@ to each other (reachable) vertex
getAllShortestPaths g f vt =
  let mfi = nodeToId g f
   in case mfi of
           Nothing -> error "getAllShortestPaths: Invalid node"
           Just fi -> unsafePerformIO $ do
             vpr <- newVectorPtr 0
             _e  <- withGraph g $ \gp ->
                      withVectorPtr vpr $ \vprp ->
                      withVs vt g $ \vtp ->
                        c_igraph_get_all_shortest_paths
                          gp
                          vprp 
                          nullPtr -- NULL
                          (fromIntegral fi)
                          vtp
                          (getNeiMode g)
             vectorPtrToVertices g vpr

foreign import ccall "get_all_shortest_paths_dijkstra"
  c_igraph_get_all_shortest_paths_dijkstra :: GraphPtr
                                           -> VectorPtrPtr
                                           -> VectorPtr
                                           -> CInt
                                           -> VsPtr
                                           -> VectorPtr
                                           -> CInt
                                           -> IO CInt

-- | 2\.10\. igraph_get_all_shortest_paths_dijkstra — Finds all shortest paths
-- (geodesics) from a vertex to all other vertices.
getAllShortestPathsDijkstra :: Graph (Weighted d) a
                            -> a                  -- ^ from
                            -> VertexSelector a   -- ^ to
                            -> [[a]]  -- ^ list of vertices along the shortest path from
                                      -- @from@ to each other (reachable) vertex
getAllShortestPathsDijkstra g f vt =
  let mfi = nodeToId g f
   in case mfi of
           Nothing -> error "getAllShortestPaths: Invalid node"
           Just fi -> unsafePerformIO $ do
             vpr <- newVectorPtr 0
             _e  <- withGraph g $ \gp ->
                    withWeights g $ \wp ->
                    withVectorPtr vpr $ \vprp ->
                    withVs vt g $ \vtp ->
                      c_igraph_get_all_shortest_paths_dijkstra
                        gp
                        vprp 
                        nullPtr -- NULL
                        (fromIntegral fi)
                        vtp
                        wp
                        (getNeiMode g)
             vectorPtrToVertices g vpr

foreign import ccall "igraph_average_path_length"
  c_igraph_average_path_length :: GraphPtr -> Ptr CDouble -> Bool -> Bool -> IO CInt

-- | 2\.11\. igraph_average_path_length — Calculates the average geodesic length
-- in a graph.
averagePathLength :: Graph d a
                  -> Bool     -- ^ Boolean, whether to consider directed paths. Ignored for undirected graphs.
                  -> Bool     -- ^ What to do if the graph is not connected. If
                              -- TRUE the average of the geodesics within the
                              -- components will be returned, otherwise the
                              -- number of vertices is used for the length of
                              -- non-existing geodesics. (The rationale behind
                              -- this is that this is always longer than the
                              -- longest possible geodesic in a graph.)
                  -> Double
averagePathLength g b1 b2 = unsafePerformIO $ do
  alloca $ \dp -> do
    _e <- withGraph g $ \gp ->
            c_igraph_average_path_length 
              gp
              dp
              b1
              b2
    realToFrac `fmap` peek dp

foreign import ccall "igraph_path_length_hist"
  c_igraph_path_length_hist :: GraphPtr -> VectorPtr -> Ptr CDouble -> Bool -> IO CInt

-- | 2\.12\. igraph_path_length_hist — Create a histogram of all shortest path lengths.
pathLengthHist :: Graph d a
               -> Bool  -- ^ Whether to consider directed paths in a directed
                       -- graph (if not zero). This argument is ignored for
                       -- undirected graphs.
               -> ([Double],Double)
pathLengthHist g b = unsafePerformIO $ do
  v <- newVector 0
  d <- alloca $ \dp -> do
    _e <- withGraph g $ \gp ->
            withVector v $ \vp ->
             c_igraph_path_length_hist
               gp
               vp
               dp
               b
    realToFrac `fmap` peek dp
  l <- vectorToList v
  return (l,d)

foreign import ccall "igraph_diameter"
  c_igraph_diameter :: GraphPtr
                    -> Ptr CInt
                    -> Ptr CInt
                    -> Ptr CInt
                    -> VectorPtr
                    -> Bool
                    -> Bool
                    -> IO CInt

-- | 2\.13\. igraph_diameter — Calculates the diameter of a graph (longest
-- geodesic).
diameter :: Graph d a
         -> Bool
         -> Bool
         -> (Int, (a,a), [a]) -- ^ the diameter of the graph, the starting/end
                              -- vertices and the longest path
diameter g b1 b2 = unsafePerformIO $ do
  alloca $ \ip -> do
    alloca $ \fip -> do
      alloca $ \tip -> do
        v  <- newVector 0
        _e <- withGraph g $ \gp ->
              withVector v $ \vp ->
                c_igraph_diameter
                  gp
                  ip
                  fip
                  tip
                  vp
                  b1
                  b2
        d  <- fromIntegral `fmap` peek ip
        fi <- fromIntegral `fmap` peek fip
        ti <- fromIntegral `fmap` peek tip
        p  <- vectorToVertices g v
        return (d, (idToNode'' g fi, idToNode'' g ti), p)

foreign import ccall "igraph_diameter_dijkstra"
  c_igraph_diameter_dijkstra
    :: GraphPtr -> VectorPtr -> Ptr CDouble -> Ptr CInt -> Ptr CInt -> VectorPtr
    -> Bool -> Bool -> IO CInt

-- | 2\.14\. igraph_diameter_dijkstra — Weighted diameter using Dijkstra's
-- algorithm, non-negative weights only.
diameterDijkstra :: Graph d a
                 -> (Double, a, a, [a]) -- ^ (diameter, source vertex, target vertex, path)
diameterDijkstra g@(G _) = unsafePerformIO $
  alloca $ \dp -> alloca $ \sp -> alloca $ \tp -> do
    v  <- newVector 0
    _e <- withGraph g $ \gp ->
          withOptionalWeights g $ \wp ->
          withVector v $ \vp ->
            c_igraph_diameter_dijkstra
              gp
              wp
              dp
              sp
              tp
              vp
              (isDirected g)
              True
    d <- peek dp
    s <- peek sp
    t <- peek tp
    path <- vectorToVertices g v
    return ( realToFrac d
           , idToNode'' g (fromIntegral s)
           , idToNode'' g (fromIntegral t)
           , path )

foreign import ccall "igraph_girth"
  c_igraph_girth :: GraphPtr -> Ptr CInt -> VectorPtr -> IO CInt

-- | 2\.15\. igraph_girth — The girth of a graph is the length of the shortest
-- circle in it.
girth :: Graph d a
      -> (Int, [a])  -- ^ girth with the shortest circle
girth g = unsafePerformIO $ do
  alloca $ \ip -> do
    v <- newVector 0
    _e <- withGraph g $ \gp ->
            withVector v $ \vp ->
              c_igraph_girth
                gp
                ip
                vp
    gr <- fromIntegral `fmap` peek ip
    s  <- vectorToVertices g v
    return (gr, s)

foreign import ccall "eccentricity"
  c_igraph_eccentricity :: GraphPtr -> VectorPtr -> VsPtr -> CInt -> IO CInt

-- | 2\.16\. igraph_eccentricity — Eccentricity of some vertices
eccentricity :: Graph d a -> VertexSelector a -> [(a,Int)]
eccentricity g vs = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
          withVs vs g $ \vsp ->
            withVector v $ \vp ->
              c_igraph_eccentricity
                gp
                vp
                vsp
                (getNeiMode g)
  l <- map round `fmap` vectorToList v
  return $ zip (selectedVertices g vs) l

foreign import ccall "igraph_radius"
  c_igraph_radius :: GraphPtr -> Ptr CDouble -> CInt -> IO CInt

-- | 2\.17\. igraph_radius — Radius of a graph
radius :: Graph d a -> Int
radius g = unsafePerformIO $ do
  alloca $ \dp -> do
    _e <- withGraph g $ \gp ->
            c_igraph_radius
              gp
              dp
              (getNeiMode g)
    round `fmap` peek dp


--------------------------------------------------------------------------------
-- 13.3 Neighborhood of a vertex

{- TODO:

3.1. igraph_neighborhood_size — Calculates the size of the neighborhood of a given vertex.

  int igraph_neighborhood_size(const igraph_t *graph,
                               igraph_vector_t *res,
                               igraph_vs_t vids,
                               igraph_integer_t order,
                               igraph_neimode_t mode);

3.2. igraph_neighborhood — Calculate the neighborhood of vertices.

  DONE:

-}

{-

foreign import ccall "neighborhood"
  c_igraph_neighborhood :: GraphPtr d a -> VectorPtrPtr -> VsPtr -> CInt -> CInt -> IO CInt

neighborhood :: VertexSelector a -> Int -> IGraph (Graph d a) [[a]]
neighborhood vs o = runUnsafeIO $ \g -> do
  v        <- newVectorPtr 10
  (_e, g') <- withGraph g $ \gp -> withVs vs g $ \vsp -> withVectorPtr v $ \vp ->
    c_igraph_neighborhood gp vp vsp (fromIntegral o) (getNeiMode g)
  ids      <- vectorPtrToList v
  return (map (map (idToNode'' g . round)) ids, g')

-}

{-

3.3. igraph_neighborhood_graphs — Create graphs from the neighborhood(s) of some vertex/vertices.

  int igraph_neighborhood_graphs(const igraph_t *graph, igraph_vector_ptr_t *res,
                                 igraph_vs_t vids, igraph_integer_t order,
                                 igraph_neimode_t mode);

-}


--------------------------------------------------------------------------------
-- 13.4 Graph Components

foreign import ccall "igraph_subcomponent"
  c_igraph_subcomponent :: GraphPtr -> VectorPtr -> CDouble -> CInt -> IO CInt

-- | 4\.1\. igraph_subcomponent — The vertices in the same component as a given vertex.
subcomponent :: Graph d a -> a -> [a]
subcomponent g a = case nodeToId g a of
  Just i -> unsafePerformIO $ do
    v <- newVector 0
    _ <- withGraph g $ \gp -> withVector v $ \vp ->
      c_igraph_subcomponent
        gp
        vp
        (fromIntegral i)
        (getNeiMode g)
    vectorToVertices g v
  _ -> []

{-

4.2. igraph_induced_subgraph — Creates a subgraph induced by the specified vertices.

  int igraph_induced_subgraph(const igraph_t *graph, igraph_t *res, 
                              const igraph_vs_t vids, igraph_subgraph_implementation_t impl);

foreign import ccall "igraph_induced_subcomponent"
  c_igraph_induced_subcomponent :: GraphPtr d a

4.3. igraph_subgraph_edges — Creates a subgraph with the specified edges and their endpoints.

  int igraph_subgraph_edges(const igraph_t *graph, igraph_t *res, 
                            const igraph_es_t eids, igraph_bool_t delete_vertices);

4.4. igraph_subgraph — Creates a subgraph induced by the specified vertices.

  int igraph_subgraph(const igraph_t *graph, igraph_t *res, 
                      const igraph_vs_t vids);

-}

{-
foreign import ccall "subgraph"
  c_igraph_subgraph :: GraphPtr d a -> GraphPtr d a -> VsPtr -> IO CInt

subgraph :: VertexSelector a -> IGraph (Graph d a) (Graph d a)
subgraph vs = do
  setVertexIds
  (_e, G Graph{ graphForeignPtr = Just subg }) <- runUnsafeIO $ \g ->
    withGraph g $ \gp -> do
      withVs vs g $ \vsp ->
        withGraph (emptyWithCtxt g) $ \gp' -> do
          c_igraph_subgraph gp gp' vsp
  g <- get
  return $ foreignGraph g subg
  --return $ G $ ForeignGraph subg (graphIdToNode g)
 where
  emptyWithCtxt :: Graph d a -> Graph d a
  emptyWithCtxt (G _) = emptyGraph
-}

{-
4.5. igraph_clusters — Calculates the (weakly or strongly) connected components in a graph.

  int igraph_clusters(const igraph_t *graph, igraph_vector_t *membership, 
                      igraph_vector_t *csize, igraph_integer_t *no,
                      igraph_connectedness_t mode);
-}

foreign import ccall "igraph_is_connected"
  c_igraph_is_connected :: GraphPtr -> Ptr CInt -> CInt -> IO CInt

-- | 4\.6\. igraph_is_connected — Decides whether the graph is (weakly or strongly) connected.
isConnected :: Graph d a -> Connectedness -> Bool
isConnected g c = unsafePerformIO $ withGraph g $ \gp -> alloca $ \b -> do
  _ <- c_igraph_is_connected gp b (fromIntegral $ fromEnum c)
  r <- peek b
  return $ r == 1

{-

4.7. igraph_decompose — Decompose a graph into connected components.

foreign import ccall "igraph_decompose"
  c_igraph_decompose :: GraphPtr -> VectorPtrPtr -> CInt -> CLong -> CInt -> IO CInt

decompose :: Graph d a -> Connectedness -> Int -> Int -> [Graph d a]
decompose g m ma mi = unsafePerformIO $ do
  vp <- newVectorPtr 0
  _e <- withGraph g $ \gp ->
        withVectorPtr vp $ \vpp ->
          c_igraph_decompose
            gp
            vpp
            (fromIntegral $ fromEnum m)
            (fromIntegral ma)
            (fromIntegral mi)
  -- vectorPtrToVertices g vp -- wrong since the vectorptr contains graphs!

4.8. igraph_decompose_destroy — Free the memory allocated by igraph_decompose().

  void igraph_decompose_destroy(igraph_vector_ptr_t *complist);

necessary? no.

4.9. igraph_biconnected_components — Calculate biconnected components

  int igraph_biconnected_components(const igraph_t *graph,
                                    igraph_integer_t *no,
                                    igraph_vector_ptr_t *tree_edges,
                                    igraph_vector_ptr_t *component_edges,
                                    igraph_vector_ptr_t *components,
                                    igraph_vector_t *articulation_points);
-}

foreign import ccall "igraph_articulation_points"
  c_igraph_articulation_points :: GraphPtr -> VectorPtr -> IO CInt

-- | 4\.10\. igraph_articulation_points — Find the articulation points in a
-- graph.
articulationPoints :: Graph d a -> [a]
articulationPoints g = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
          c_igraph_articulation_points
            gp
            vp
  vectorToVertices g v


--------------------------------------------------------------------------------
-- 13.5 Centrality Measures

foreign import ccall "closeness"
  c_igraph_closeness :: GraphPtr -> VectorPtr -> VsPtr -> CInt -> VectorPtr -> IO CInt

-- | 5\.1\. igraph_closeness — Closeness centrality calculations for some
-- vertices.
closeness :: Ord a => Graph d a -> VertexSelector a -> Map a Double
closeness g vs = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withOptionalWeights g $ \wp ->
        withVs vs g $ \vsp ->
        withVector v $ \vp ->
          c_igraph_closeness
            gp
            vp
            vsp
            (getNeiMode g)
            wp
  scores <- vectorToList v
  return $ M.fromList $ zip (selectedVertices g vs) scores

foreign import ccall "betweenness"
  c_igraph_betweenness :: GraphPtr -> VectorPtr -> VsPtr -> Bool -> VectorPtr -> Bool -> IO CInt

-- | 5\.2\. igraph_betweenness — Betweenness centrality of some vertices.
betweenness :: Ord a => Graph d a -> VertexSelector a -> Map a Double
betweenness g vs = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withOptionalWeights g $ \wp ->
        withVs vs g $ \vsp ->
        withVector v $ \vp ->
          c_igraph_betweenness
            gp
            vp
            vsp
            True -- should be OK for all graphs
            wp
            True -- should be OK for all graphs
  scores <- vectorToList v
  return $ M.fromList $ zip (selectedVertices g vs) scores

foreign import ccall "igraph_edge_betweenness"
  c_igraph_edge_betweenness :: GraphPtr -> VectorPtr -> Bool -> VectorPtr -> IO CInt

-- | 5\.3\. igraph_edge_betweenness — Betweenness centrality of the edges.
edgeBetweenness :: Ord (Edge d a) => Graph d a -> Map (Edge d a) Double
edgeBetweenness g = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withOptionalWeights g $ \wp ->
        withVector v $ \vp ->
          c_igraph_edge_betweenness
            gp
            vp
            True
            wp
  scores <- vectorToList v
  return $ M.fromList $ zip (F.toList $ edges g) scores

{-
5.4. igraph_pagerank — Calculates the Google PageRank for the specified vertices.

  int igraph_pagerank(const igraph_t *graph,
                      igraph_vector_t *vector,
                      igraph_real_t *value,
                      const igraph_vs_t vids,
                      igraph_bool_t directed,
                      igraph_real_t damping, 
                      const igraph_vector_t *weights,
                      igraph_arpack_options_t *options);

5.5. igraph_pagerank_old — Calculates the Google PageRank for the specified vertices.

  int igraph_pagerank_old(const igraph_t *graph, igraph_vector_t *res, 
                          const igraph_vs_t vids, igraph_bool_t directed,
                          igraph_integer_t niter, igraph_real_t eps, 
                          igraph_real_t damping, igraph_bool_t old);

5.6. igraph_personalized_pagerank — Calculates the personalized Google PageRank for the specified vertices.

  int igraph_personalized_pagerank(const igraph_t *graph, igraph_vector_t *vector,
                                   igraph_real_t *value, const igraph_vs_t vids,
                                   igraph_bool_t directed, igraph_real_t damping, 
                                   igraph_vector_t *reset,
                                   const igraph_vector_t *weights,
                                   igraph_arpack_options_t *options);

5.7. igraph_personalized_pagerank_vs — Calculates the personalized Google PageRank for the specified vertices.

  int igraph_personalized_pagerank_vs(const igraph_t *graph, igraph_vector_t *vector,
                                      igraph_real_t *value, const igraph_vs_t vids,
                                      igraph_bool_t directed, igraph_real_t damping, 
                                      igraph_vs_t reset_vids,
                                      const igraph_vector_t *weights,
                                      igraph_arpack_options_t *options);
-}

foreign import ccall "constraint"
  c_igraph_constraint :: GraphPtr -> VectorPtr -> VsPtr -> VectorPtr -> IO CInt

-- | 5\.8\. igraph_constraint — Burt's constraint scores.
constraint :: Ord a => Graph d a -> VertexSelector a -> Map a Double
constraint g vs = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withOptionalWeights g $ \wp ->
        withVector v $ \vp ->
        withVs vs g $ \vsp ->
          c_igraph_constraint
            gp
            vp
            vsp
            wp
  scores <- vectorToList v
  return $ M.fromList $ zip (selectedVertices g vs) scores

foreign import ccall "maxdegree"
  c_igraph_maxdegree :: GraphPtr -> Ptr CInt -> VsPtr -> CInt -> Bool -> IO CInt

-- | 5\.9\. igraph_maxdegree — Calculate the maximum degree in a graph (or set
-- of vertices).
maxdegree :: Graph d a
          -> VertexSelector a
          -> Bool -- ^ count self-loops?
          -> Int
maxdegree g vs b = unsafePerformIO $
  withGraph g $ \gp ->
  withVs vs g $ \vsp ->
  alloca $ \ip -> do
    _e <- c_igraph_maxdegree
            gp
            ip
            vsp
            (getNeiMode g)
            b
    fromIntegral `fmap` peek ip

foreign import ccall "strength"
  c_igraph_strength :: GraphPtr -> VectorPtr -> VsPtr -> CInt -> Bool -> VectorPtr -> IO CInt

-- | 5\.10\. igraph_strength — Strength of the vertices, weighted vertex degree
-- in other words.
strength :: Ord a
         => Graph d a
         -> VertexSelector a
         -> Bool -- ^ count self-loops?
         -> Map a Int
strength g vs b = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withVs vs g $ \vsp ->
        withOptionalWeights g $ \wp ->
          c_igraph_strength
            gp
            vp
            vsp
            (getNeiMode g)
            b
            wp
  scores <- vectorToList v
  return $ M.fromList $ zip (selectedVertices g vs) (map round scores)

{-
5.11. igraph_eigenvector_centrality — Eigenvector centrality of the vertices

  int igraph_eigenvector_centrality(const igraph_t *graph, 
                                    igraph_vector_t *vector,
                                    igraph_real_t *value, 
                                    igraph_bool_t directed, igraph_bool_t scale,
                                    const igraph_vector_t *weights,
                                    igraph_arpack_options_t *options);

5.12. igraph_hub_score — Kleinberg's hub scores

  int igraph_hub_score(const igraph_t *graph, igraph_vector_t *vector,
                       igraph_real_t *value, igraph_bool_t scale,
                       const igraph_vector_t *weights,
                       igraph_arpack_options_t *options);

5.13. igraph_authority_score — Kleinerg's authority scores

  int igraph_authority_score(const igraph_t *graph, igraph_vector_t *vector,
                             igraph_real_t *value, igraph_bool_t scale,
                             const igraph_vector_t *weights,
                             igraph_arpack_options_t *options);

-}

--------------------------------------------------------------------------------
-- 13.6 Estimating Centrality Measures

foreign import ccall "closeness_estimate"
  c_igraph_closeness_estimate :: GraphPtr -> VectorPtr -> VsPtr -> CInt -> CDouble -> VectorPtr -> IO CInt

-- | 6\.1\. igraph_closeness_estimate — Closeness centrality estimations for
-- some vertices.
closenessEstimate :: Ord a => Graph d a
                  -> VertexSelector a
                  -> Int  -- ^ cutoff
                  -> Map a Double
closenessEstimate g vs cutoff = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withVs vs g $ \vsp ->
        withOptionalWeights g $ \wp ->
          c_igraph_closeness_estimate
            gp
            vp
            vsp
            (getNeiMode g)
            (fromIntegral cutoff)
            wp
  scores <- vectorToList v
  return $ M.fromList $ zip (selectedVertices g vs) scores

foreign import ccall "betweenness_estimate"
  c_igraph_betweenness_estimate :: GraphPtr -> VectorPtr -> VsPtr -> Bool -> CDouble
                                -> VectorPtr -> Bool -> IO CInt

-- | 6\.2\. igraph_betweenness_estimate — Estimated betweenness centrality of
-- some vertices.
betweennessEstimate :: Ord a
                    => Graph d a
                    -> VertexSelector a
                    -> Int -- ^ cutoff
                    -> Map a Double
betweennessEstimate g@(G _) vs cutoff = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withVs vs g $ \vsp ->
        withOptionalWeights g $ \wp ->
          c_igraph_betweenness_estimate
            gp
            vp
            vsp
            (isDirected g)
            (fromIntegral cutoff)
            wp
            True -- should be OK for most graphs
  scores <- vectorToList v
  return $ M.fromList $ zip (selectedVertices g vs) scores

foreign import ccall "igraph_edge_betweenness_estimate"
  c_igraph_edge_betweenness_estimate :: GraphPtr -> VectorPtr -> Bool -> CDouble -> VectorPtr -> IO CInt

-- | 6\.3\. igraph_edge_betweenness_estimate — Estimated betweenness centrality
-- of the edges.
edgeBetweennessEstimate :: Ord (Edge d a)
                        => Graph d a
                        -> Int -- ^ cutoff
                        -> Map (Edge d a) Double
edgeBetweennessEstimate g@(G _) cutoff = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withOptionalWeights g $ \wp ->
          c_igraph_edge_betweenness_estimate
            gp
            vp
            (isDirected g)
            (fromIntegral cutoff)
            wp
  scores <- vectorToList v
  return $ M.fromList $ zip (F.toList $ edges g) scores

--------------------------------------------------------------------------------
-- 13.7 Centralization

{-
7.1. igraph_centralization — Calculate the centralization score from the node level scores

  igraph_real_t igraph_centralization(const igraph_vector_t *scores,
                                      igraph_real_t theoretical_max,
                                      igraph_bool_t normalized);
-}

foreign import ccall "igraph_centralization_degree"
  c_igraph_centralization_degree :: GraphPtr -> VectorPtr -> CInt -> Bool
                                 -> Ptr CDouble -> Ptr CDouble -> Bool -> IO CInt

-- | 7\.2\. igraph_centralization_degree — Calculate vertex degree and graph
-- centralization
centralizationDegree :: Ord a => Graph d a
                     -> Bool -- ^ consider loop edges?
                     -> Bool -- ^ normalize centralization score?
                     -> (Map a Double, Double, Double) -- ^ (node-level degree scores, centralization scores, theoretical max)
centralizationDegree g l n = unsafePerformIO $ do
  v  <- newVector 0
  alloca $ \cp ->
    alloca $ \tp -> do
      _e <- withGraph g $ \gp ->
            withVector v $ \vp ->
              c_igraph_centralization_degree
                gp
                vp
                (getNeiMode g)
                l
                cp
                tp
                n
      scores <- vectorToList v
      c <- peek cp
      t <- peek tp
      return ( M.fromList (zip (F.toList (nodes g)) scores)
             , realToFrac c
             , realToFrac t )

foreign import ccall "igraph_centralization_betweenness"
  c_igraph_centralization_betweenness :: GraphPtr -> VectorPtr -> Bool -> Bool
                                      -> Ptr CDouble -> Ptr CDouble -> Bool -> IO CInt

-- | 7\.3\. igraph_centralization_betweenness — Calculate vertex betweenness and
-- graph centralization
centralizationBetweenness :: Ord a => Graph d a
                          -> Bool -- ^ normalize centralization score?
                          -> (Map a Double, Double, Double) -- ^ (node-level degree scores, centralization scores, theoretical max)
centralizationBetweenness g@(G _) n = unsafePerformIO $
  alloca $ \cp -> alloca $ \tp -> do
    v <- newVector 0
    _e <- withGraph g $ \gp ->
          withVector v $ \vp ->
            c_igraph_centralization_betweenness
              gp
              vp
              (isDirected g)
              False
              cp
              tp
              n
    scores <- vectorToList v
    c <- peek cp
    t <- peek tp
    return ( M.fromList (zip (F.toList (nodes g)) scores)
           , realToFrac c
           , realToFrac t )

foreign import ccall "igraph_centralization_closeness"
  c_igraph_centralization_closeness
    :: GraphPtr -> VectorPtr -> CInt -> Ptr CDouble -> Ptr CDouble -> Bool -> IO CInt

-- | 7\.4\. igraph_centralization_closeness — Calculate vertex closeness and
-- graph centralization
centralizationCloseness :: Ord a => Graph d a
                        -> Bool -- ^ normalize centralization score?
                        -> (Map a Double, Double, Double) -- ^ (node-level degree scores, centralization scores, theoretical max)
centralizationCloseness g n = unsafePerformIO $
  alloca $ \cp -> alloca $ \tp -> do
    v  <- newVector 0
    _e <- withGraph g $ \gp ->
          withVector v $ \vp ->
            c_igraph_centralization_closeness
              gp
              vp
              (getNeiMode g)
              cp
              tp
              n
    scores <- vectorToList v
    c <- peek cp
    t <- peek tp
    return ( M.fromList (zip (F.toList (nodes g)) scores)
           , realToFrac c
           , realToFrac t )

{-
7.5. igraph_centralization_eigenvector_centrality — Calculate eigenvector centrality scores and graph centralization

  int igraph_centralization_eigenvector_centrality(const igraph_t *graph,
                                                   igraph_vector_t *vector,
                                                   igraph_real_t *value,
                                                   igraph_bool_t directed,
                                                   igraph_bool_t scale,
                                                   igraph_arpack_options_t *options,
                                                   igraph_real_t *centralization,
                                                   igraph_real_t *theoretical_max,
                                                   igraph_bool_t normalized);
-}

foreign import ccall "igraph_centralization_degree_tmax"
  c_igraph_centralization_degree_tmax
    :: GraphPtr -> CInt -> CInt -> Bool -> Ptr CDouble -> IO CInt

-- | 7\.6\. igraph_centralization_degree_tmax — Theoretical maximum for graph
-- centralization based on degree
centralizationDegreeTMax :: Either (Graph d a) Int -- ^ either graph or number of nodes
                         -> Bool -- ^ consider loop edges?
                         -> Double
centralizationDegreeTMax egi b = unsafePerformIO $
  alloca $ \rp -> do
    _e <- withGraph' egi $ \gp ->
            c_igraph_centralization_degree_tmax
              gp
              i
              neimode
              b
              rp
    r <- peek rp
    return ( realToFrac r )
 where
  withGraph' (Left g)  = withGraph g
  withGraph' (Right _) = (\f -> f nullPtr)
  i       = either (const 0) fromIntegral egi
  neimode = either getNeiMode (const (fromIntegral (fromEnum Out))) egi

foreign import ccall "igraph_centralization_betweenness_tmax"
  c_igraph_centralization_betweenness_tmax
    :: GraphPtr -> CInt -> Bool -> Ptr CDouble -> IO CInt

-- | 7\.7\. igraph_centralization_betweenness_tmax — Theoretical maximum for
-- graph centralization based on betweenness
centralizationBetweennessTMax :: Either (Graph d a) Int
                              -> Double
centralizationBetweennessTMax egi = unsafePerformIO $
  alloca $ \rp -> do
    _e <- withGraph' egi $ \gp ->
            c_igraph_centralization_betweenness_tmax
              gp
              i
              directed
              rp
    r <- peek rp
    return ( realToFrac r )
 where
  withGraph' (Left g)  = withGraph g
  withGraph' (Right _) = (\f -> f nullPtr)
  i        = either (const 0) fromIntegral egi
  directed = either (\g@(G _) -> isDirected g) (const True) egi

foreign import ccall "igraph_centralization_closeness_tmax"
  c_igraph_centralization_closeness_tmax
    :: GraphPtr -> CInt -> CInt -> Ptr CDouble -> IO CInt

-- | 7\.8\. igraph_centralization_closeness_tmax — Theoretical maximum for graph
-- centralization based on closeness
centralizationClosenessTMax :: Either (Graph d a) Int -> Double
centralizationClosenessTMax egi = unsafePerformIO $
  alloca $ \rp -> do
    _e <- withGraph' egi $ \gp ->
            c_igraph_centralization_closeness_tmax
              gp
              i
              neimode
              rp
    r <- peek rp
    return ( realToFrac r )
 where
  withGraph' (Left g)  = withGraph g
  withGraph' (Right _) = (\f -> f nullPtr)
  i       = either (const 0) fromIntegral egi
  neimode = either getNeiMode (const (fromIntegral (fromEnum Out))) egi

{-
7.9. igraph_centralization_eigenvector_centrality_tmax — Theoretical maximum centralization for eigenvector centrality

  int igraph_centralization_eigenvector_centrality_tmax(const igraph_t *graph,
                                                        igraph_integer_t nodes,
                                                        igraph_bool_t directed,
                                                        igraph_bool_t scale, 
                                                        igraph_real_t *res);
-}

--------------------------------------------------------------------------------
-- 13.8 Similarity Measures

foreign import ccall "bibcoupling"
  c_igraph_bibcoupling :: GraphPtr -> MatrixPtr -> VsPtr -> IO CInt

-- | 8\.1\. `igraph_bibcoupling` — Bibliographic coupling.
--
-- The bibliographic coupling of two vertices is the number of other vertices
-- they both cite, `igraph_bibcoupling()` calculates this. The bibliographic
-- coupling score for each given vertex and all other vertices in the graph will
-- be calculated.
bibCoupling :: Graph d a -> VertexSelector a -> [(a,[(a,Int)])]
bibCoupling g vs = unsafePerformIO $ do
  let selected = selectedVertices g vs
      nrows    = length selected
      ncols    = numberOfNodes g
  m  <- newMatrix nrows ncols
  _e <- withGraph g $ \gp ->
        withVs vs g $ \vsp ->
        withMatrix m $ \mp ->
          c_igraph_bibcoupling
            gp
            mp
            vsp
  ids <- map (map round) `fmap` matrixToList m
  return $ zip selected (map (zip (nodes g)) ids)

foreign import ccall "cocitation"
  c_igraph_cocitation :: GraphPtr -> MatrixPtr -> VsPtr -> IO CInt

-- | 8\.2\. `igraph_cocitation` — Cocitation coupling.
--
-- Two vertices are cocited if there is another vertex citing both of them.
-- `igraph_cocitation()` simply counts how many times two vertices are cocited.
-- The cocitation score for each given vertex and all other vertices in the
-- graph will be calculated.
cocitation :: Graph d a -> VertexSelector a -> [(a,[(a,Int)])]
cocitation g vs = unsafePerformIO $ do
  let selected = selectedVertices g vs
      nrows    = length selected
      ncols    = numberOfNodes g
  m  <- newMatrix nrows ncols
  _e <- withGraph g $ \gp ->
        withVs vs g $ \vsp ->
        withMatrix m $ \mp ->
          c_igraph_cocitation
            gp
            mp
            vsp
  ids <- map (map round) `fmap` matrixToList m
  return $ zip selected (map (zip (nodes g)) ids)

foreign import ccall "similarity_jaccard"
  c_igraph_similarity_jaccard :: GraphPtr -> MatrixPtr -> VsPtr -> CInt -> Bool -> IO CInt

-- | 8\.3\. `igraph_similarity_jaccard` — Jaccard similarity coefficient for the
-- given vertices.
--
-- The Jaccard similarity coefficient of two vertices is the number of common
-- neighbors divided by the number of vertices that are neighbors of at least
-- one of the two vertices being considered. This function calculates the
-- pairwise Jaccard similarities for some (or all) of the vertices.
similarityJaccard :: Graph d a
                  -> VertexSelector a
                  -> Bool -- ^ Whether to include the vertices themselves in the neighbor sets
                  -> [(a,[(a,Double)])]
similarityJaccard g vs loops = unsafePerformIO $ do
  let selected = selectedVertices g vs
      nrows    = length selected
  m  <- newMatrix nrows nrows
  _e <- withGraph g $ \gp ->
        withVs vs g $ \vsp ->
        withMatrix m $ \mp ->
          c_igraph_similarity_jaccard
            gp
            mp
            vsp
            (getNeiMode g)
            loops
  ids <- matrixToList m
  return $ zip selected (map (zip selected) ids)

foreign import ccall "igraph_similarity_jaccard_pairs"
  c_igraph_similarity_jaccard_pairs
    :: GraphPtr
    -> VectorPtr
    -> VectorPtr
    -> CInt
    -> Bool
    -> IO CInt

-- | 8\.4\. `igraph_similarity_jaccard_pairs` — Jaccard similarity coefficient for
-- given vertex pairs.
--
-- The Jaccard similarity coefficient of two vertices is the number of common
-- neighbors divided by the number of vertices that are neighbors of at least
-- one of the two vertices being considered. This function calculates the
-- pairwise Jaccard similarities for a list of vertex pairs.
similarityJaccardPairs :: Graph d a
                       -> [Edge d a]
                       -> Bool -- ^ Whether to include the vertices themselves in the neighbor sets
                       -> [(Edge d a,Double)]
similarityJaccardPairs g@(G _) es loops = unsafePerformIO $ do
  p   <- listToVector $
           foldr (\e r -> nodeToId'' g (edgeFrom e):nodeToId'' g (edgeTo e):r)
                 []
                 es
  r   <- newVector (length es)
  _e  <- withGraph g $ \gp ->
         withVector r $ \rp ->
         withVector p $ \pp ->
           c_igraph_similarity_jaccard_pairs
             gp
             rp
             pp
             (getNeiMode g)
             loops
  res <- vectorToList r
  return $ zip es res

foreign import ccall "similarity_jaccard_es"
  c_igraph_similarity_jaccard_es
    :: GraphPtr
    -> VectorPtr
    -> EsPtr
    -> CInt
    -> Bool
    -> IO CInt

-- | 8\.5\. `igraph_similarity_jaccard_es` — Jaccard similarity coefficient for a
-- given edge selector.
--
-- The Jaccard similarity coefficient of two vertices is the number of common
-- neighbors divided by the number of vertices that are neighbors of at least
-- one of the two vertices being considered. This function calculates the
-- pairwise Jaccard similarities for the endpoints of edges in a given edge
-- selector.
similarityJaccardEs
  :: Graph d a
  -> EdgeSelector d a
  -> Bool -- ^ Whether to include the vertices themselves in the neighbor sets
  -> [(Edge d a, Double)]
similarityJaccardEs g es b = unsafePerformIO $ do
  let sel = selectedEdges g es
  v  <- newVector (length sel)
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withEs es g $ \esp ->
          c_igraph_similarity_jaccard_es
            gp
            vp
            esp
            (getNeiMode g)
            b
  l <- vectorToList v
  return $ zip sel l

foreign import ccall "similarity_dice"
  c_igraph_similarity_dice
    :: GraphPtr
    -> MatrixPtr
    -> VsPtr
    -> CInt
    -> Bool
    -> IO CInt

-- | 8\.6\. `igraph_similarity_dice` — Dice similarity coefficient.
--
-- The Dice similarity coefficient of two vertices is twice the number of
-- common neighbors divided by the sum of the degrees of the vertices. This
-- function calculates the pairwise Dice similarities for some (or all) of the
-- vertices.
similarityDice :: Graph d a
               -> VertexSelector a
               -> Bool -- ^ Whether to include the vertices themselves as their own neighbors
               -> [(a,[(a,Double)])]
similarityDice g vs loops = unsafePerformIO $ do
  let sel = selectedVertices g vs
      n   = length sel
  m  <- newMatrix n n
  _e <- withGraph g $ \gp ->
        withVs vs g $ \vsp ->
        withMatrix m $ \mp ->
          c_igraph_similarity_dice
            gp
            mp
            vsp
            (getNeiMode g)
            loops
  res <- matrixToList m
  return $ zip sel (map (zip sel) res)

foreign import ccall "igraph_similarity_dice_pairs"
  c_igraph_similarity_dice_pairs
    :: GraphPtr
    -> VectorPtr
    -> VectorPtr
    -> CInt
    -> Bool
    -> IO CInt

-- | 8\.7\. `igraph_similarity_dice_pairs` — Dice similarity coefficient for given
-- vertex pairs.
--
-- The Dice similarity coefficient of two vertices is twice the number of
-- common neighbors divided by the sum of the degrees of the vertices. This
-- function calculates the pairwise Dice similarities for a list of vertex
-- pairs.
similarityDicePairs :: Graph d a
                    -> [Edge d a]
                    -> Bool -- ^ Whether to include the vertices themselves as their own neighbors
                    -> [(Edge d a, Double)]
similarityDicePairs g@(G _) es loops = unsafePerformIO $ do
  v  <- listToVector $
          foldr (\e r -> nodeToId'' g (edgeFrom e) : nodeToId'' g (edgeTo e) : r)
                [] es
  r  <- newVector (length es)
  _e <- withGraph g $ \gp ->
        withVector r $ \rp ->
        withVector v $ \vp ->
          c_igraph_similarity_dice_pairs
            gp
            rp
            vp
            (getNeiMode g)
            loops
  res <- vectorToList r
  return $ zip es res

foreign import ccall "similarity_dice_es"
  c_igraph_similarity_dice_es
    :: GraphPtr
    -> VectorPtr
    -> EsPtr
    -> CInt
    -> Bool
    -> IO CInt

-- | 8\.8\. `igraph_similarity_dice_es` — Dice similarity coefficient for a given
-- edge selector.
--
-- The Dice similarity coefficient of two vertices is twice the number of common
-- neighbors divided by the sum of the degrees of the vertices. This function
-- calculates the pairwise Dice similarities for the endpoints of edges in a
-- given edge selector.
similarityDiceEs
  :: Graph d a
  -> EdgeSelector d a
  -> Bool -- ^ Whether to include the vertices themselves as their own neighbors
  -> [(Edge d a, Double)]
similarityDiceEs g es b = unsafePerformIO $ do
  let sel = selectedEdges g es
  v  <- newVector (length sel)
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withEs es g $ \esp ->
          c_igraph_similarity_dice_es
            gp
            vp
            esp
            (getNeiMode g)
            b
  l <- vectorToList v
  return $ zip sel l

foreign import ccall "similarity_inverse_log_weighted"
  c_igraph_similarity_inverse_log_weighted
    :: GraphPtr
    -> MatrixPtr
    -> VsPtr
    -> CInt
    -> IO CInt

-- | 8\.9\. `igraph_similarity_inverse_log_weighted` — Vertex similarity based on
-- the inverse logarithm of vertex degrees.
--
-- The inverse log-weighted similarity of two vertices is the number of their
-- common neighbors, weighted by the inverse logarithm of their degrees. It is
-- based on the assumption that two vertices should be considered more similar
-- if they share a low-degree common neighbor, since high-degree common
-- neighbors are more likely to appear even by pure chance.
--
-- Isolated vertices will have zero similarity to any other vertex.
-- Self-similarities are not calculated.
--
-- See the following paper for more details: Lada A. Adamic and Eytan Adar:
-- Friends and neighbors on the Web. Social Networks, 25(3):211-230, 2003.
similarityInverseLogWeighted
  :: Graph d a
  -> VertexSelector a
  -> [(a,[(a,Double)])]
similarityInverseLogWeighted g vs = unsafePerformIO $ do
  let sel   = selectedVertices g vs
      nrows = length sel
      ncols = numberOfNodes g
  m  <- newMatrix nrows ncols
  _e <- withGraph g $ \gp ->
        withMatrix m $ \mp ->
        withVs vs g $ \vsp ->
          c_igraph_similarity_inverse_log_weighted
            gp
            mp
            vsp
            (getNeiMode g)
  r  <- matrixToList m
  return $ zip sel (map (zip (nodes g)) r)

--------------------------------------------------------------------------------
-- 13.9 Spanning Trees

foreign import ccall "igraph_minimum_spanning_tree"
  c_igraph_minimum_spanning_tree
    :: GraphPtr
    -> VectorPtr
    -> VectorPtr
    -> IO CInt

-- | 9\.1\. `igraph_minimum_spanning_tree` — Calculates one minimum spanning tree of a graph.
--
-- If the graph has more minimum spanning trees (this is always the case, except
-- if it is a forest) this implementation returns only the same one.
--
-- Directed graphs are considered as undirected for this computation.
--
-- If the graph is not connected then its minimum spanning forest is returned.
-- This is the set of the minimum spanning trees of each component.
minimumSpanningTree :: Graph d a -> [Edge d a]
minimumSpanningTree g@(G _) = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withOptionalWeights g $ \wp ->
          c_igraph_minimum_spanning_tree
            gp
            vp
            wp
  vectorToEdges g v

{- 9.2. igraph_minimum_spanning_tree_unweighted — Calculates one minimum
 - spanning tree of an unweighted graph.

int igraph_minimum_spanning_tree_unweighted(const igraph_t *graph, 
              igraph_t *mst);

-- TODO
-}


--------------------------------------------------------------------------------
-- 13.10 Transitivity or Clustering Coefficient

foreign import ccall "igraph_transitivity_undirected"
  c_igraph_transitivity_undirected
    :: GraphPtr
    -> Ptr CDouble
    -> CInt
    -> IO CInt

-- | 10\.1\. `igraph_transitivity_undirected` — Calculates the transitivity
-- (clustering coefficient) of a graph.
--
-- The transitivity measures the probability that two neighbors of a vertex are
-- connected. More precisely, this is the ratio of the triangles and connected
-- triples in the graph, the result is a single real number. Directed graphs are
-- considered as undirected ones.
--
-- Note that this measure is different from the local transitivity measure (see
-- `igraph_transitivity_local_undirected()` ) as it calculates a single value for
-- the whole graph. See the following reference for more details:
--
-- S. Wasserman and K. Faust: Social Network Analysis: Methods and Applications.
-- Cambridge: Cambridge University Press, 1994.
--
-- Clustering coefficient is an alternative name for transitivity.
transitivityUndirected :: Graph d a -> Double
transitivityUndirected g = unsafePerformIO $ alloca $ \dp -> do
  _e <- withGraph g $ \gp ->
          c_igraph_transitivity_undirected
            gp
            dp
            (fromIntegral $ fromEnum TransitivityZero)
  realToFrac `fmap` peek dp


foreign import ccall "transitivity_local_undirected"
  c_igraph_transitivity_local_undirected
    :: GraphPtr
    -> VectorPtr
    -> VsPtr
    -> CInt
    -> IO CInt

-- | 10\.2\. `igraph_transitivity_local_undirected` — Calculates the local
-- transitivity (clustering coefficient) of a graph.
--
-- The transitivity measures the probability that two neighbors of a vertex are
-- connected. In case of the local transitivity, this probability is calculated
-- separately for each vertex.
--
-- Note that this measure is different from the global transitivity measure (see
-- igraph_transitivity_undirected() ) as it calculates a transitivity value for
-- each vertex individually. See the following reference for more details:
--
-- D. J. Watts and S. Strogatz: Collective dynamics of small-world networks.
-- Nature 393(6684):440-442 (1998).
--
-- Clustering coefficient is an alternative name for transitivity.
transitivityLocalUndirected :: Graph d a -> VertexSelector a -> [(a,Double)]
transitivityLocalUndirected g vs = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withVs vs g $ \vsp ->
          c_igraph_transitivity_local_undirected
            gp
            vp
            vsp
            (fromIntegral $ fromEnum TransitivityZero)
  let sel = selectedVertices g vs
  r <- vectorToList v
  return $ zip sel r

foreign import ccall "igraph_transitivity_avglocal_undirected"
  c_igraph_transitivity_avglocal_undirected
    :: GraphPtr
    -> Ptr CDouble
    -> CInt
    -> IO CInt

-- | 10\.3\. `igraph_transitivity_avglocal_undirected` — Average local transitivity
-- (clustering coefficient).
--
-- The transitivity measures the probability that two neighbors of a vertex are
-- connected. In case of the average local transitivity, this probability is
-- calculated for each vertex and then the average is taken. Vertices with less
-- than two neighbors require special treatment, they will either be left out
-- from the calculation or they will be considered as having zero transitivity,
-- depending on the mode argument.
--
-- Note that this measure is different from the global transitivity measure (see
-- `igraph_transitivity_undirected()` ) as it simply takes the average local
-- transitivity across the whole network. See the following reference for more
-- details:
--
-- D. J. Watts and S. Strogatz: Collective dynamics of small-world networks.
-- Nature 393(6684):440-442 (1998).
--
-- Clustering coefficient is an alternative name for transitivity.
transitivityAvglocalUndirected :: Graph d a -> Double
transitivityAvglocalUndirected g = unsafePerformIO $ alloca $ \dp -> do
  _e <- withGraph g $ \gp ->
          c_igraph_transitivity_avglocal_undirected
            gp
            dp
            (fromIntegral $ fromEnum TransitivityZero)
  realToFrac `fmap` peek dp

foreign import ccall "transitivity_barrat"
  c_igraph_transitivity_barrat
    :: GraphPtr
    -> VectorPtr
    -> VsPtr
    -> VectorPtr
    -> CInt
    -> IO CInt

-- | 10\.4\. `igraph_transitivity_barrat` — Weighted transitivity, as defined by A.
-- Barrat.
--
-- This is a local transitivity, i.e. a vertex-level index. For a given vertex
-- i, from all triangles in which it participates we consider the weight of the
-- edges incident on i. The transitivity is the sum of these weights divided by
-- twice the strength of the vertex (see `igraph_strength()`) and the degree of
-- the vertex minus one. See Alain Barrat, Marc Barthelemy, Romualdo
-- Pastor-Satorras, Alessandro Vespignani: The architecture of complex weighted
-- networks, Proc. Natl. Acad. Sci. USA 101, 3747 (2004) at
-- http://arxiv.org/abs/cond-mat/0311416 for the exact formula.
transitivityBarrat :: Graph d a -> VertexSelector a -> [(a,Double)]
transitivityBarrat g vs = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withVs vs g $ \vsp ->
        withOptionalWeights g $ \wp ->
          c_igraph_transitivity_barrat
            gp
            vp
            vsp
            wp
            (fromIntegral $ fromEnum TransitivityZero)
  r <- vectorToList v
  return $ zip (selectedVertices g vs) r


--------------------------------------------------------------------------------
-- 13.11 Directedness conversion

-- Done in Haskell

--------------------------------------------------------------------------------
-- 13.12 Spectral properties

foreign import ccall "igraph_laplacian"
  c_igraph_laplacian
    :: GraphPtr
    -> MatrixPtr
    -> SpMatrixPtr
    -> Bool
    -> VectorPtr
    -> IO CInt

-- | 12\.1\. `igraph_laplacian` — Returns the Laplacian matrix of a graph
--
-- The graph Laplacian matrix is similar to an adjacency matrix but contains
-- -1's instead of 1's and the vertex degrees are included in the diagonal. So
-- the result for edge i--j is -1 if i!=j and is equal to the degree of vertex i
-- if i==j. igraph_laplacian will work on a directed graph; in this case, the
-- diagonal will contain the out-degrees. Loop edges will be ignored.
--
-- The normalized version of the Laplacian matrix has 1 in the diagonal and
-- -1/sqrt(d[i]d[j]) if there is an edge from i to j.
--
-- The first version of this function was written by Vincent Matossian.
laplacian :: Graph d a
          -> Bool -- ^ Whether to create a normalized Laplacian matrix
          -> [[Double]]
laplacian g norm = unsafePerformIO $ do
  m  <- newMatrix 0 0
  _e <- withGraph g $ \gp ->
        withMatrix m $ \mp ->
        withOptionalWeights g $ \wp ->
          c_igraph_laplacian
            gp
            mp
            nullPtr
            norm
            wp
  matrixToList m

--------------------------------------------------------------------------------
-- 13.13 Non-simple graphs: multiple and loop edges

{- This whole chapter might not be necessary since we can't have edges from a
 - vertex to itself or multiple edges in our graph due to the use of Map/Sets!

foreign import ccall "igraph_is_simple"
  c_igraph_is_simple
    :: GraphPtr
    -> Ptr Bool
    -> IO CInt

-- | 13\.1\. `igraph_is_simple` — Decides whether the input graph is a simple graph.
--
-- A graph is a simple graph if it does not contain loop edges and multiple
-- edges.
isSimple :: Graph d a -> Bool
isSimple g = unsafePerformIO $ alloca $ \bp -> do
  _e <- withGraph g $ \gp ->
        c_igraph_is_simple
          gp
          bp
  peek bp

foreign import ccall "is_loop"
  c_igraph_is_loop :: GraphPtr -> VectorPtr -> EsPtr -> IO CInt

-- | 13\.2\. `igraph_is_loop` — Find the loop edges in a graph.
--
--A loop edge is an edge from a vertex to itself.
isLoop :: Graph d a -> EdgeSelector d a -> [(Edge d a, Bool)]
isLoop g es = unsafePerformIO $ do
  let sel = selectedEdges g es
  v  <- newVector (length sel)
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withEs es g $ \esp ->
          c_igraph_is_loop
            gp
            vp
            esp
  l <- vectorToList v
  return $ zip sel (map (0 /=) l)
-}

--------------------------------------------------------------------------------
-- 13.14 Mixing patterns

foreign import ccall "igraph_assortativity_nominal"
  c_igraph_assortativity_nominal
    :: GraphPtr
    -> VectorPtr
    -> Ptr CDouble
    -> Bool
    -> IO CInt

-- | 14\.1\. `igraph_assortativity_nominal` — Assortativity of a graph based on
-- vertex categories
--
-- Assuming the vertices of the input graph belong to different categories, this
-- function calculates the assortativity coefficient of the graph. The
-- assortativity coefficient is between minus one and one and it is one if all
-- connections stay within categories, it is minus one, if the network is
-- perfectly disassortative. For a randomly connected network it is
-- (asymptotically) zero.
--
-- See equation (2) in M. E. J. Newman: Mixing patterns in networks, Phys. Rev.
-- E 67, 026126 (2003) (http://arxiv.org/abs/cond-mat/0209450) for the proper
-- definition.
assortativityNominal
  :: (Eq vertexType)
  => Graph d (vertexType, a)
  -> Bool -- ^ whether to consider edge directions in a directed graph. It is
          -- ignored for undirected graphs
  -> Double
assortativityNominal g b = unsafePerformIO $ alloca $ \dp -> do
  let all_types = map fst $ nodes g
      types     = map fst $ zip [(0 :: Int)..] (nub all_types)
  v  <- listToVector types
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
          c_igraph_assortativity_nominal
            gp
            vp
            dp
            b
  realToFrac `fmap` peek dp

foreign import ccall "igraph_assortativity"
  c_igraph_assortativity
    :: GraphPtr
    -> VectorPtr
    -> VectorPtr
    -> Ptr CDouble
    -> Bool
    -> IO CInt

-- | 14\.2\. `igraph_assortativity` — Assortativity based on numeric properties of
-- vertices
--
-- This function calculates the assortativity coefficient of the input graph.
-- This coefficient is basically the correlation between the actual connectivity
-- patterns of the vertices and the pattern expected from the distribution of
-- the vertex types.
--
-- See equation (21) in M. E. J. Newman: Mixing patterns in networks, Phys. Rev.
-- E 67, 026126 (2003) (http://arxiv.org/abs/cond-mat/0209450) for the proper
-- definition. The actual calculation is performed using equation (26) in the
-- same paper for directed graphs, and equation (4) in M. E. J. Newman:
-- Assortative mixing in networks, Phys. Rev. Lett. 89, 208701 (2002)
-- (http://arxiv.org/abs/cond-mat/0205405/) for undirected graphs.
assortativity
  :: (Eq vertexTypeIncoming, Eq vertexTypeOutgoing)
  => Graph d (vertexTypeIncoming, vertexTypeOutgoing, a)
  -> Bool -- ^ whether to consider edge directions for directed graphs. It is
          -- ignored for undirected graphs
  -> Double
assortativity g b = unsafePerformIO $ alloca $ \dp -> do
  let (all_types_inc, all_types_out) = unzip [ (i,o) | (i,o,_) <- nodes g ]
      types_inc = map fst $ zip [(0 :: Int)..] (nub all_types_inc)
      types_out = map fst $ zip [(0 :: Int)..] (nub all_types_out)
  v1 <- listToVector types_inc
  v2 <- listToVector types_out
  _e <- withGraph g $ \gp ->
        withVector v1 $ \vp1 ->
        withVector v2 $ \vp2 ->
          c_igraph_assortativity
            gp
            vp1
            vp2
            dp
            b
  realToFrac `fmap` peek dp

foreign import ccall "igraph_assortativity_degree"
  c_igraph_assortativity_degree
    :: GraphPtr
    -> Ptr CDouble
    -> Bool
    -> IO CInt

-- | 14\.3\. `igraph_assortativity_degree` — Assortativity of a graph based on vertex
-- degree
--
-- Assortativity based on vertex degree, please see the discussion at the
-- documentation of igraph_assortativity() for details.
assortativityDegree
  :: Graph d a
  -> Bool -- ^ whether to consider edge directions for directed graphs. This
          -- argument is ignored for undirected graphs. Supply `True` here to
          -- do the natural thing, i.e. use directed version of the measure for
          -- directed graphs and the undirected version for undirected graphs.
  -> Double
assortativityDegree g b = unsafePerformIO $ alloca $ \dp -> do
  _e <- withGraph g $ \gp ->
          c_igraph_assortativity_degree
            gp
            dp
            b
  realToFrac `fmap` peek dp

--------------------------------------------------------------------------------
-- 13.15 K-Cores

foreign import ccall "igraph_coreness"
  c_igraph_coreness
    :: GraphPtr
    -> VectorPtr
    -> CInt
    -> IO CInt

-- | 15\.1\. `igraph_coreness` — Finding the coreness of the vertices in a network.
--
-- The k-core of a graph is a maximal subgraph in which each vertex has at least
-- degree k. (Degree here means the degree in the subgraph of course.). The
-- coreness of a vertex is the highest order of a k-core containing the vertex.
--
-- This function implements the algorithm presented in Vladimir Batagelj, Matjaz
-- Zaversnik: An O(m) Algorithm for Cores Decomposition of Networks.
coreness :: Graph d a -> [(Double, a)]
coreness g = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
          c_igraph_coreness
            gp
            vp
            (getNeiMode g)
  r  <- vectorToList v
  return $ zip r (nodes g)

--------------------------------------------------------------------------------
-- 13.16 Topological sorting, directed acyclic graphs

foreign import ccall "igraph_is_dag"
  c_igraph_is_dag
    :: GraphPtr
    -> Ptr Bool
    -> IO CInt

-- | 16\.1\. `igraph_is_dag` — Checks whether a graph is a directed acyclic graph
-- (DAG) or not.
--
-- A directed acyclic graph (DAG) is a directed graph with no cycles.
isDAG :: Graph d a -> Bool
isDAG g = unsafePerformIO $ alloca $ \bp -> do
  _e <- withGraph g $ \gp ->
          c_igraph_is_dag
            gp
            bp
  peek bp

foreign import ccall "igraph_topological_sorting"
  c_igraph_topological_sorting
    :: GraphPtr
    -> VectorPtr
    -> CInt
    -> IO CInt

-- | 16\.2\. `igraph_topological_sorting` — Calculate a possible topological sorting
-- of the graph.
--
-- A topological sorting of a directed acyclic graph is a linear ordering of its
-- nodes where each node comes before all nodes to which it has edges. Every DAG
-- has at least one topological sort, and may have many. This function returns a
-- possible topological sort among them. If the graph is not acyclic (it has at
-- least one cycle), a partial topological sort is returned and a warning is
-- issued.
topologicalSorting
  :: Graph d a
  -> [a]
topologicalSorting g = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
          c_igraph_topological_sorting
            gp
            vp
            (getNeiMode g)
  vectorToVertices g v

foreign import ccall "igraph_feedback_arc_set"
  c_igraph_feedback_arc_set
    :: GraphPtr
    -> VectorPtr
    -> VectorPtr
    -> CInt
    -> IO CInt

-- | 16\.3\. `igraph_feedback_arc_set` — Calculates a feedback arc set of the graph
-- using different
--
-- A feedback arc set is a set of edges whose removal makes the graph acyclic.
-- We are usually interested in minimum feedback arc sets, i.e. sets of edges
-- whose total weight is minimal among all the feedback arc sets.
--
-- For undirected graphs, the problem is simple: one has to find a maximum
-- weight spanning tree and then remove all the edges not in the spanning tree.
-- For directed graphs, this is an NP-hard problem, and various heuristics are
-- usually used to find an approximate solution to the problem. This function
-- implements a few of these heuristics.
feedbackArcSet
  :: Graph d a
  -> FASAlgorithm
  -> [a]
feedbackArcSet g algo = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
        withOptionalWeights g $ \wp ->
          c_igraph_feedback_arc_set
            gp
            vp
            wp
            (fromIntegral $ fromEnum algo)
  vectorToVertices g v

--------------------------------------------------------------------------------
-- 13.17 Maximum cardinality search, graph decomposition, chordal graphs

foreign import ccall "igraph_maximum_cardinality_search"
  c_igraph_maximum_cardinality_search
    :: GraphPtr
    -> VectorPtr
    -> VectorPtr
    -> IO CInt

-- | 17\.1\. `igraph_maximum_cardinality_search` — Maximum cardinality search
--
-- This function implements the maximum cardinality search algorithm discussed
-- in Robert E Tarjan and Mihalis Yannakakis: Simple linear-time algorithms to
-- test chordality of graphs, test acyclicity of hypergraphs, and selectively
-- reduce acyclic hypergraphs. SIAM Journal of Computation 13, 566--579, 1984.
maximumCardinalitySearch
  :: Graph d a
  -> [(Int, a)]
maximumCardinalitySearch g = unsafePerformIO $ do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
          c_igraph_maximum_cardinality_search
            gp
            vp
            nullPtr
  r <- vectorToList v
  return $ zip (map round r) (nodes g)

foreign import ccall "igraph_is_chordal"
  c_igraph_is_chordal
    :: GraphPtr
    -> VectorPtr
    -> VectorPtr
    -> Ptr Bool
    -> VectorPtr
    -> GraphPtr
    -> IO CInt

-- | 17\.2\. `igraph_is_chordal` — Decides whether a graph is chordal
--
-- A graph is chordal if each of its cycles of four or more nodes has a chord,
-- which is an edge joining two nodes that are not adjacent in the cycle. An
-- equivalent definition is that any chordless cycles have at most three nodes.
isChordal
  :: Graph d a
  -> (Bool, [Edge d a]) -- ^ returns a list of fill-in edges to make the graph chordal
isChordal g@(G _) = unsafePerformIO $ alloca $ \bp -> do
  v  <- newVector 0
  _e <- withGraph g $ \gp ->
        withVector v $ \vp ->
          c_igraph_is_chordal
            gp
            nullPtr
            nullPtr
            bp
            vp
            nullPtr
  b  <- peek bp
  as <- vectorToVertices g v
  let mkEdges (f:t:r) = (toEdge f t : mkEdges r)
      mkEdges []      = []
      mkEdges [_]     = error "Error in `isChordal': Invalid number of arguments to `mkEdges'"
  return (b, mkEdges as)


--------------------------------------------------------------------------------
-- 13.18 Matchings

--------------------------------------------------------------------------------
-- 13.19 Line graphs

--------------------------------------------------------------------------------
-- 13.20 Unfolding a graph into a tree

--------------------------------------------------------------------------------
-- 13.21 Other Operations

