{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DefaultSignatures #-}
{-# OPTIONS_HADDOCK hide #-}
module Data.Vector.Unboxing.Internal
  (Unboxable(Rep, coercion) -- 'coercion' is exported
  ,Vector(UnboxingVector)
  ,MVector(UnboxingMVector)
  ,coerceVector
  ,liftCoercion
  ,vectorCoercion
  ,toUnboxedVector
  ,fromUnboxedVector
  ,toUnboxedMVector
  ,fromUnboxedMVector
  ) where
import qualified Data.Vector.Generic as G
import qualified Data.Vector.Generic.Mutable as GM
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector.Unboxed.Mutable as UM
import qualified Data.Vector.Fusion.Bundle as Bundle
import Data.Coerce
import Data.Type.Coercion
import Data.Semigroup
import Data.Int
import Data.Word
import qualified Data.Complex
import qualified Data.Functor.Identity
import qualified Data.Functor.Const
import qualified Data.Ord
import qualified Data.Monoid
import qualified Data.MonoTraversable -- from mono-traversable
import qualified Data.Sequences       -- from mono-traversable
import GHC.Exts (IsList(..))
import Control.DeepSeq (NFData(..))
import Text.Read (Read(..),readListPrecDefault)

-- | Types that can be stored in unboxed vectors ('Vector' and 'MVector').
--
-- This class consists of three components:
--
-- * The underlying (primitive) type @Rep a@.
-- * The witness that @Rep a@ is an instance of 'U.Unbox'.
--   (i.e. the underlying type can be stored in 'Data.Vector.Unboxed.Vector')
-- * The witness that @a@ and @Rep a@ has the same representation.
--   This is essentially the constraint @Coercible a (Rep a)@,
--   but making it a class constraint
--   (i.e. defining this class as @(..., Coercible a (Rep a)) => Unboxable a@)
--   leads to an unwanted leak of the @Coercible@ constraint.
--   So a trick is used here to hide the @Coercible@ constraint from user code.
--
-- This class can be derived with @GeneralizedNewtypeDeriving@
-- (you may need @UndecidableInstances@ in addition).
class (U.Unbox (Rep a) {-, Coercible a (Rep a) -}) => Unboxable a where
  -- | The underlying type of @a@.  Must be an instance of 'U.Unbox'.
  type Rep a

  -- A hack to hide @Coercible a (Rep a)@ from outside...
  -- This method should always be inlined.
  coercion :: Coercion a (Rep a)
  default coercion :: Coercible a (Rep a) => Coercion a (Rep a)
  coercion = Coercion
  {-# INLINE coercion #-}

-- This declaration is not possible:
-- type role Vector representational

newtype Vector a = UnboxingVector (U.Vector (Rep a))
newtype MVector s a = UnboxingMVector (UM.MVector s (Rep a))

type instance G.Mutable Vector = MVector

-- Coercible a b is not strictly necessary in this function, but the data constructors should be visible on the call site.
coerceVector :: (Coercible a b, Rep a ~ Rep b) => Vector a -> Vector b
coerceVector = coerce
{-# INLINE coerceVector #-}

liftCoercion :: (Rep a ~ Rep b) => Coercion a b -> Coercion (Vector a) (Vector b)
liftCoercion Coercion = Coercion
{-# INLINE liftCoercion #-}

vectorCoercion :: (Coercible a b, Rep a ~ Rep b) => Coercion (Vector a) (Vector b)
vectorCoercion = Coercion
{-# INLINE vectorCoercion #-}

toUnboxedVector :: (Rep a ~ a) => Vector a -> U.Vector a
toUnboxedVector (UnboxingVector v) = v
{-# INLINE toUnboxedVector #-}

fromUnboxedVector :: (Rep a ~ a) => U.Vector a -> Vector a
fromUnboxedVector v = UnboxingVector v
{-# INLINE fromUnboxedVector #-}

toUnboxedMVector :: (Rep a ~ a) => MVector s a -> U.MVector s a
toUnboxedMVector (UnboxingMVector v) = v
{-# INLINE toUnboxedMVector #-}

fromUnboxedMVector :: (Rep a ~ a) => U.MVector s a -> MVector s a
fromUnboxedMVector v = UnboxingMVector v
{-# INLINE fromUnboxedMVector #-}

-- This is not possible:
-- instance (Coercible a b, Rep a ~ Rep b) => Coercible (Vector a) (Vector b)

instance (Unboxable a) => IsList (Vector a) where
  type Item (Vector a) = a
  fromList = G.fromList
  fromListN = G.fromListN
  toList = G.toList
  {-# INLINE fromList #-}
  {-# INLINE fromListN #-}
  {-# INLINE toList #-}

instance (Eq a, Unboxable a) => Eq (Vector a) where
  xs == ys = Bundle.eq (G.stream xs) (G.stream ys)
  xs /= ys = not (Bundle.eq (G.stream xs) (G.stream ys))
  {-# INLINE (==) #-}
  {-# INLINE (/=) #-}

instance (Ord a, Unboxable a) => Ord (Vector a) where
  compare xs ys = Bundle.cmp (G.stream xs) (G.stream ys)
  {-# INLINE compare #-}

instance (Show a, Unboxable a) => Show (Vector a) where
  showsPrec = G.showsPrec
  {-# INLINE showsPrec #-}

instance (Read a, Unboxable a) => Read (Vector a) where
  readPrec = G.readPrec
  readListPrec = readListPrecDefault
  {-# INLINE readPrec #-}
  {-# INLINE readListPrec #-}

instance (Unboxable a) => Semigroup (Vector a) where
  (<>) = (G.++)
  sconcat = G.concatNE
  {-# INLINE (<>) #-}
  {-# INLINE sconcat #-}

instance (Unboxable a) => Monoid (Vector a) where
  mempty = G.empty
  mappend = (<>)
  mconcat = G.concat
  {-# INLINE mempty #-}
  {-# INLINE mappend #-}
  {-# INLINE mconcat #-}

instance NFData (Vector a) where
  rnf !_ = () -- the content is unboxed

instance (Unboxable a) => GM.MVector MVector a where
  basicLength (UnboxingMVector mv)                           = GM.basicLength mv
  basicUnsafeSlice i l (UnboxingMVector mv)                  = UnboxingMVector (GM.basicUnsafeSlice i l mv)
  basicOverlaps (UnboxingMVector mv) (UnboxingMVector mv')   = GM.basicOverlaps mv mv'
  basicUnsafeNew l                                           = UnboxingMVector <$> GM.basicUnsafeNew l
  basicInitialize (UnboxingMVector mv)                       = GM.basicInitialize mv
  basicUnsafeReplicate i x                                   = case coercion @ a of Coercion -> UnboxingMVector <$> GM.basicUnsafeReplicate i (coerce x)
  basicUnsafeRead (UnboxingMVector mv) i                     = case coercion @ a of Coercion -> coerce <$> GM.basicUnsafeRead mv i
  basicUnsafeWrite (UnboxingMVector mv) i x                  = case coercion @ a of Coercion -> GM.basicUnsafeWrite mv i (coerce x)
  basicClear (UnboxingMVector mv)                            = GM.basicClear mv
  basicSet (UnboxingMVector mv) x                            = case coercion @ a of Coercion -> GM.basicSet mv (coerce x)
  basicUnsafeCopy (UnboxingMVector mv) (UnboxingMVector mv') = GM.basicUnsafeCopy mv mv'
  basicUnsafeMove (UnboxingMVector mv) (UnboxingMVector mv') = GM.basicUnsafeMove mv mv'
  basicUnsafeGrow (UnboxingMVector mv) n                     = UnboxingMVector <$> GM.basicUnsafeGrow mv n
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicOverlaps #-}
  {-# INLINE basicUnsafeNew #-}
  {-# INLINE basicInitialize #-}
  {-# INLINE basicUnsafeRead #-}
  {-# INLINE basicUnsafeWrite #-}
  {-# INLINE basicClear #-}
  {-# INLINE basicSet #-}
  {-# INLINE basicUnsafeCopy #-}
  {-# INLINE basicUnsafeMove #-}
  {-# INLINE basicUnsafeGrow #-}

instance (Unboxable a) => G.Vector Vector a where
  basicUnsafeFreeze (UnboxingMVector mv)                  = UnboxingVector <$> G.basicUnsafeFreeze mv
  basicUnsafeThaw (UnboxingVector v)                      = UnboxingMVector <$> G.basicUnsafeThaw v
  basicLength (UnboxingVector v)                          = G.basicLength v
  basicUnsafeSlice i l (UnboxingVector v)                 = UnboxingVector (G.basicUnsafeSlice i l v)
  basicUnsafeIndexM (UnboxingVector v) i                  = case coercion @ a of Coercion -> coerce <$> G.basicUnsafeIndexM v i
  basicUnsafeCopy (UnboxingMVector mv) (UnboxingVector v) = G.basicUnsafeCopy mv v
  elemseq (UnboxingVector v) x y                          = case coercion @ a of Coercion -> G.elemseq v (coerce x) y
  {-# INLINE basicUnsafeFreeze #-}
  {-# INLINE basicUnsafeThaw #-}
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicUnsafeIndexM #-}
  {-# INLINE basicUnsafeCopy #-}
  {-# INLINE elemseq #-}

-----

-- Classes from mono-traversable

type instance Data.MonoTraversable.Element (Vector a) = a

instance (Unboxable a) => Data.MonoTraversable.MonoFunctor (Vector a) where
  omap = G.map
  {-# INLINE omap #-}

instance (Unboxable a) => Data.MonoTraversable.MonoFoldable (Vector a) where
  ofoldMap f = G.foldr (mappend . f) mempty
  ofoldr = G.foldr
  ofoldl' = G.foldl'
  otoList = G.toList
  oall = G.all
  oany = G.any
  onull = G.null
  olength = G.length
  olength64 = fromIntegral . G.length
  -- ocompareLength : use default
  -- otraverse_ : use default
  -- ofor_ : use default
  -- omapM_ : use default (G.mapM_ requires a Monad, unfortunately)
  -- oforM_ : use default (G.forM_ requires a Monad, unfortunately)
  ofoldlM = G.foldM
  -- ofoldMap1Ex : use default
  ofoldr1Ex = G.foldr1
  ofoldl1Ex' = G.foldl1'
  headEx = G.head
  lastEx = G.last
  unsafeHead = G.unsafeHead
  unsafeLast = G.unsafeLast
  maximumByEx = G.maximumBy
  minimumByEx = G.minimumBy
  oelem = G.elem
  onotElem = G.notElem
  {-# INLINE ofoldMap #-}
  {-# INLINE ofoldr #-}
  {-# INLINE ofoldl' #-}
  {-# INLINE otoList #-}
  {-# INLINE oall #-}
  {-# INLINE oany #-}
  {-# INLINE onull #-}
  {-# INLINE olength #-}
  {-# INLINE olength64 #-}
  {-# INLINE ofoldlM #-}
  {-# INLINE ofoldr1Ex #-}
  {-# INLINE ofoldl1Ex' #-}
  {-# INLINE headEx #-}
  {-# INLINE lastEx #-}
  {-# INLINE unsafeHead #-}
  {-# INLINE unsafeLast #-}
  {-# INLINE maximumByEx #-}
  {-# INLINE minimumByEx #-}
  {-# INLINE oelem #-}
  {-# INLINE onotElem #-}

instance (Unboxable a) => Data.MonoTraversable.MonoTraversable (Vector a) where
  otraverse f v = let !n = G.length v
                  in G.fromListN n <$> traverse f (G.toList v)
  omapM = Data.MonoTraversable.otraverse
  {-# INLINE otraverse #-}
  {-# INLINE omapM #-}

instance (Unboxable a) => Data.MonoTraversable.MonoPointed (Vector a) where
  opoint = G.singleton
  {-# INLINE opoint #-}

instance (Unboxable a) => Data.MonoTraversable.GrowingAppend (Vector a)

instance (Unboxable a) => Data.Sequences.SemiSequence (Vector a) where
  type Index (Vector a) = Int
  intersperse = Data.Sequences.defaultIntersperse
  reverse = G.reverse
  find = G.find
  sortBy = Data.Sequences.vectorSortBy
  cons = G.cons
  snoc = G.snoc
  {-# INLINE intersperse #-}
  {-# INLINE reverse #-}
  {-# INLINE find #-}
  {-# INLINE sortBy #-}
  {-# INLINE cons #-}
  {-# INLINE snoc #-}

instance (Unboxable a) => Data.Sequences.IsSequence (Vector a) where
  fromList = G.fromList
  lengthIndex = G.length
  break = G.break
  span = G.span
  dropWhile = G.dropWhile
  takeWhile = G.takeWhile
  splitAt = G.splitAt
  -- unsafeSplitAt : use default
  take = G.take
  unsafeTake = G.unsafeTake
  drop = G.drop
  unsafeDrop = G.unsafeDrop
  -- dropEnd : use default
  partition = G.partition
  uncons v | G.null v = Nothing
           | otherwise = Just (G.head v, G.tail v)
  unsnoc v | G.null v = Nothing
           | otherwise = Just (G.init v, G.last v)
  filter = G.filter
  filterM = G.filterM
  replicate = G.replicate
  replicateM = G.replicateM
  -- groupBy : use default
  -- groupAllOn : use default
  -- subsequences : use default
  -- permutations : use default
  tailEx = G.tail
  -- tailMay : use default
  initEx = G.init
  -- initMay : use default
  unsafeTail = G.unsafeTail
  unsafeInit = G.unsafeInit
  index = (G.!?)
  indexEx = (G.!)
  unsafeIndex = G.unsafeIndex
  -- splitWhen : use default
  {-# INLINE fromList #-}
  {-# INLINE lengthIndex #-}
  {-# INLINE break #-}
  {-# INLINE span #-}
  {-# INLINE dropWhile #-}
  {-# INLINE takeWhile #-}
  {-# INLINE splitAt #-}
  {-# INLINE take #-}
  {-# INLINE unsafeTake #-}
  {-# INLINE drop #-}
  {-# INLINE unsafeDrop #-}
  {-# INLINE partition #-}
  {-# INLINE uncons #-}
  {-# INLINE unsnoc #-}
  {-# INLINE filter #-}
  {-# INLINE filterM #-}
  {-# INLINE replicate #-}
  {-# INLINE replicateM #-}
  {-# INLINE tailEx #-}
  {-# INLINE initEx #-}
  {-# INLINE unsafeTail #-}
  {-# INLINE unsafeInit #-}
  {-# INLINE index #-}
  {-# INLINE indexEx #-}
  {-# INLINE unsafeIndex #-}

-----

-- Unboxable instances

instance Unboxable Bool where   type Rep Bool = Bool
instance Unboxable Char where   type Rep Char = Char
instance Unboxable Double where type Rep Double = Double
instance Unboxable Float where  type Rep Float = Float
instance Unboxable Int where    type Rep Int = Int
instance Unboxable Int8 where   type Rep Int8 = Int8
instance Unboxable Int16 where  type Rep Int16 = Int16
instance Unboxable Int32 where  type Rep Int32 = Int32
instance Unboxable Int64 where  type Rep Int64 = Int64
instance Unboxable Word where   type Rep Word = Word
instance Unboxable Word8 where  type Rep Word8 = Word8
instance Unboxable Word16 where type Rep Word16 = Word16
instance Unboxable Word32 where type Rep Word32 = Word32
instance Unboxable Word64 where type Rep Word64 = Word64
instance Unboxable () where     type Rep () = ()

instance (Unboxable a) => Unboxable (Data.Complex.Complex a) where
  type Rep (Data.Complex.Complex a) = Data.Complex.Complex (Rep a)
  coercion = case coercion @ a of Coercion -> Coercion
  {-# INLINE coercion #-}

instance (Unboxable a, Unboxable b) => Unboxable (a, b) where
  type Rep (a, b) = (Rep a, Rep b)
  coercion = case coercion @ a of
    Coercion -> case coercion @ b of
      Coercion -> Coercion
  {-# INLINE coercion #-}

instance (Unboxable a, Unboxable b, Unboxable c) => Unboxable (a, b, c) where
  type Rep (a, b, c) = (Rep a, Rep b, Rep c)
  coercion = case coercion @ a of
    Coercion -> case coercion @ b of
      Coercion -> case coercion @ c of
        Coercion -> Coercion
  {-# INLINE coercion #-}

instance (Unboxable a, Unboxable b, Unboxable c, Unboxable d) => Unboxable (a, b, c, d) where
  type Rep (a, b, c, d) = (Rep a, Rep b, Rep c, Rep d)
  coercion = case coercion @ a of
    Coercion -> case coercion @ b of
      Coercion -> case coercion @ c of
        Coercion -> case coercion @ d of
          Coercion -> Coercion
  {-# INLINE coercion #-}

instance (Unboxable a, Unboxable b, Unboxable c, Unboxable d, Unboxable e) => Unboxable (a, b, c, d, e) where
  type Rep (a, b, c, d, e) = (Rep a, Rep b, Rep c, Rep d, Rep e)
  coercion = case coercion @ a of
    Coercion -> case coercion @ b of
      Coercion -> case coercion @ c of
        Coercion -> case coercion @ d of
          Coercion -> case coercion @ e of
            Coercion -> Coercion
  {-# INLINE coercion #-}

instance (Unboxable a, Unboxable b, Unboxable c, Unboxable d, Unboxable e, Unboxable f) => Unboxable (a, b, c, d, e, f) where
  type Rep (a, b, c, d, e, f) = (Rep a, Rep b, Rep c, Rep d, Rep e, Rep f)
  coercion = case coercion @ a of
    Coercion -> case coercion @ b of
      Coercion -> case coercion @ c of
        Coercion -> case coercion @ d of
          Coercion -> case coercion @ e of
            Coercion -> case coercion @ f of
              Coercion -> Coercion
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Functor.Identity.Identity a) where
  type Rep (Data.Functor.Identity.Identity a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Functor.Const.Const a b) where
  type Rep (Data.Functor.Const.Const a b) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Semigroup.Min a) where
  type Rep (Data.Semigroup.Min a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Semigroup.Max a) where
  type Rep (Data.Semigroup.Max a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Semigroup.First a) where
  type Rep (Data.Semigroup.First a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Semigroup.Last a) where
  type Rep (Data.Semigroup.Last a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Semigroup.WrappedMonoid a) where
  type Rep (Data.Semigroup.WrappedMonoid a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Monoid.Dual a) where
  type Rep (Data.Monoid.Dual a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance Unboxable Data.Monoid.All where
  type Rep Data.Monoid.All = Bool

instance Unboxable Data.Monoid.Any where
  type Rep Data.Monoid.Any = Bool

instance (Unboxable a) => Unboxable (Data.Monoid.Sum a) where
  type Rep (Data.Monoid.Sum a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Monoid.Product a) where
  type Rep (Data.Monoid.Product a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}

instance (Unboxable a) => Unboxable (Data.Ord.Down a) where
  type Rep (Data.Ord.Down a) = Rep a
  coercion = coerce (coercion @ a)
  {-# INLINE coercion #-}
