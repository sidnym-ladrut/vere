module UntypedLambda where

import ClassyPrelude

import Bound
import Control.Monad.Writer
import Data.Deriving (deriveEq1, deriveOrd1, deriveRead1, deriveShow1)
import qualified Data.Function as F
import Data.List (elemIndex)
import Data.Maybe (fromJust)
import qualified Data.Set as Set
import Data.Void

import Nock
import Noun

type Nat = Int

data Exp a
  = Var a
  | App (Exp a) (Exp a)
  | Lam (Scope () Exp a)
  | Atm Atom
  | Cel (Exp a) (Exp a)
  | IsC (Exp a)
  | Suc (Exp a)
  | Eql (Exp a) (Exp a)
  | Ift (Exp a) (Exp a) (Exp a)
  | Let (Exp a) (Scope () Exp a)
  -- Really should be Set a (Exp a) (Exp a), but making that work would require
  -- something like
  -- https://github.com/ekmett/bound/blob/master/examples/Imperative.hs
  -- and I really really can't be bothered right now.
  | Set (Exp a) (Exp a) (Exp a)
  | Jet Atom (Exp a)
  | Fix (Scope () Exp a)
  deriving (Functor, Foldable, Traversable)

deriveEq1   ''Exp
deriveOrd1  ''Exp
deriveRead1 ''Exp
deriveShow1 ''Exp
makeBound   ''Exp

deriving instance Eq a => Eq (Exp a)
deriving instance Ord a => Ord (Exp a)
deriving instance Read a => Read (Exp a)
deriving instance Show a => Show (Exp a)

lam :: Eq a => a -> Exp a -> Exp a
lam v e = Lam (abstract1 v e)

ledt :: Eq a => a -> Exp a -> Exp a -> Exp a
ledt v e f = Let e (abstract1 v f)

set :: a -> Exp a -> Exp a -> Exp a
set v e f = Set (Var v) e f

fix :: Eq a => a -> Exp a -> Exp a
fix v e = Fix (abstract1 v e)

eval :: (Eq a) => Exp a -> Exp a
eval = \case
  e@Var{} -> e
  e@Lam{} -> e
  (App e f) -> case eval e of
    (Lam s) -> instantiate1 (eval f) s
    e' -> (App e' (eval f))
  e@Atm{} -> e
  (Cel e f) -> Cel (eval e) (eval f)
  (IsC e) -> case eval e of
    Atm{} -> Atm 1
    Cel{} -> Atm 0
    Lam{} -> Atm 0  -- ehhhh
    Var{} -> error "eval: free variable"
    _ -> error "eval: implementation error"
  (Suc e) -> case eval e of
    Atm a -> Atm (a + 1)
    _ -> error "eval: cannot take successor of non-atom"
  (Ift e t f) -> case eval e of
    Atm 0 -> eval t
    Atm 1 -> eval f
    _ -> error "eval: not a boolean"
  (Let e s) -> instantiate1 (eval e) s
  (Set _ _ _) -> error "eval: Set: FIXME not sure"
  Jet _ e -> eval e
  Fix s -> F.fix (flip instantiate1 s)  -- Who knows, it may even work!

-- 6, 30, 126, 510, ...
oldDeBruijn :: Nat -> Axis
oldDeBruijn = toAxis . go
  where
    go = \case
      0 -> [R,L]
      n -> [R,R] ++ go (n - 1)

-- | Raw de Bruijn
data Exp'
  = Var' Nat
  | App' Exp' Exp'
  | Lam' Exp'
  deriving (Eq, Ord, Read, Show)

toExp' :: Exp a -> Exp'
toExp' = go \v -> error "toExp': free variable"
  where
    go :: (a -> Nat) -> Exp a -> Exp'
    go env = \case
      Var v   -> Var' (env v)
      App e f -> App' (go env e) (go env f)
      Lam s   -> Lam' (go env' (fromScope s))
        where
          env' = \case
            B () -> 0
            F v  -> 1 + env v

cell :: Nock -> Nock -> Nock
cell (N1 n) (N1 m) = N1 (C n m)
cell ef ff = NC ef ff

-- | The old calling convention; i.e., what the (%-, |=) sublanguage of hoon
-- compiles to
old :: Exp a -> Nock
old = go \v -> error "old: free variable"
  where
    go :: (a -> Path) -> Exp a -> Nock
    go env = \case
      Var v     -> N0 (toAxis (env v))
      App e f   -> app (go env e) (go (\v -> R : env v) f)
      Lam s     -> lam (nockToNoun (go env' (fromScope s)))
        where
          env' = \case
            B () -> [R,L]
            F v  -> [R,R] ++ env v
      Cel e f   -> cell (go env e) (go env f)
      IsC e     -> N3 (go env e)
      Suc e     -> N4 (go env e)
      Eql e f   -> N5 (go env e) (go env f)
      Ift e t f -> N6 (go env e) (go env t) (go env f)
      Let e s   -> N8 (go env e) (go env' (fromScope s))
        where
          env' = \case
            B () -> [L]
            F v  -> R : env v
      Set e f g -> case e of
        Var v -> N10 (toAxis (env v), go env f) (go env g)
      Jet{}     -> error "old: Old-style jetting not supported"
      Fix{}     -> error "old: This convention doesn't use fix"

    app ef ff =
      N8
        ef  -- =+ callee so we don't modify the orig's bunt
        (N9 2
          (N10 (6, ff)
            (N0 2)))
    lam ff =
      N8  -- pushes onto the context
        (N1 (A 0))  -- a bunt value (in hoon, actually depends on type)
        (NC  -- then celles (N8 would also work, but hoon doesn't)
          (N1 ff)  -- the battery (nock code)
          (N0 1))  -- onto the pair of bunt and context

data CExp a
  = CVar a
  | CApp (CExp a) (CExp a)
  | CLam [a] (CExp (Var () Int))
  | CAtm Atom
  | CCel (CExp a) (CExp a)
  | CIsC (CExp a)
  | CSuc (CExp a)
  | CEql (CExp a) (CExp a)
  | CIft (CExp a) (CExp a) (CExp a)
  | CLet (CExp a) (CExp (Var () a))
  | CSet a (CExp a) (CExp a)
  | CJet Atom (CExp a)
  | CFix (CExp (Var () a))
  deriving (Functor, Foldable, Traversable)

deriveEq1   ''CExp
deriveOrd1  ''CExp
deriveRead1 ''CExp
deriveShow1 ''CExp

deriving instance Eq a => Eq (CExp a)
deriving instance Ord a => Ord (CExp a)
deriving instance Read a => Read (CExp a)
deriving instance Show a => Show (CExp a)

toCopy :: Ord a => Exp a -> CExp b
toCopy = fst . runWriter . go \v -> error "toCopy: free variable"
  where
    go :: Ord a => (a -> c) -> Exp a -> Writer (Set a) (CExp c)
    go env = \case
      Var v     -> writer (CVar (env v), singleton v)
      App e f   -> CApp <$> go env e <*> go env f
      Atm a     -> pure (CAtm a)
      Cel e f   -> CCel <$> go env e <*> go env f
      IsC e     -> CIsC <$> go env e
      Suc e     -> CSuc <$> go env e
      Eql e f   -> CEql <$> go env e <*> go env f
      Ift e t f -> CIft <$> go env e <*> go env t <*> go env f
      Set e f g -> case e of
        Var v -> do
          tell (singleton v)
          cf <- go env f
          cg <- go env g
          pure (CSet (env v) cf cg)
        _ -> error "toCopy: duuude that's not how you set things"
      Jet a e   -> CJet a <$> go env e
      Let e s   -> do
        ce <- go env e
        cf <- retcon removeBound (go (fmap env) (fromScope s))
        pure (CLet ce cf)
      Fix s     -> CFix <$> retcon removeBound (go (fmap env) (fromScope s))
      Lam s -> writer (CLam (map env $ toList usedLexicals) ce, usedLexicals)
        where
          (ce, usedVars) = runWriter $ go env' $ fromScope s
          env' = \case
            B () -> B ()
            F v  -> F (Set.findIndex v usedLexicals)
          usedLexicals = removeBound usedVars

    removeBound :: (Ord a, Ord b) => Set (Var b a) -> Set a
    removeBound = mapMaybeSet \case
      B _ -> Nothing
      F v -> Just v

-- | Like censor, except you can change the type of the log
retcon :: (w -> uu) -> Writer w a -> Writer uu a
retcon f = mapWriter \(a, m) -> (a, f m)

-- I begin to wonder why there aren't primary abstractions around filtering.
mapMaybeSet :: (Ord a, Ord b) => (a -> Maybe b) -> Set a -> Set b
mapMaybeSet f = setFromList . mapMaybe f . toList

-- Possible improvements:
--   - store the copied values in a tree rather than list
--   - avoid a nock 8 if nothing is copied
--   - a "quote and unquote" framework for nock code generation (maybe)
--   - something about error messages when a variable is set but then not read
copyToNock :: CExp a -> Nock
copyToNock = go \v -> error "copyToNock: free variable"
  where
    -- if you comment out this declaration, you get a type error!
    go :: (a -> Path) -> CExp a -> Nock
    go env = \case
      CVar v -> N0 (toAxis (env v))
      CApp e f -> N2 (go env f) (go env e)
      CAtm a -> N1 (A a)
      CCel e f -> cell (go env e) (go env f)
      CIsC e -> N3 (go env e)
      CSuc e -> N4 (go env e)
      CEql e f -> N5 (go env e) (go env f)
      CIft e t f -> N6 (go env e) (go env t) (go env f)
      CJet a e -> jet a (go env e)
      CSet v e f -> N10 (toAxis (env v), go env e) (go env f)
      CLet e f -> N8 (go env e) (go env' f)
        where
          env' = \case
            B () -> [L]
            F v  -> R : env v
      CLam vs e -> lam (map (go env . CVar) vs) (go env' e)
        where
          env' = \case
            B () -> [R]
            F i  -> L : replicate i R ++ [L]
      CFix e -> N8 (go env' e) (N2 (N0 1) (N0 2))
        where
          env' = \case
            B () -> [L]
            F v  -> R : env v

    jet a ef =
      NC
        (N1
          (C (A 11)
          (C (A FastAtom)
            (C (A 1) (A a)))))
        ef
    lam vfs ef =
      NC (N1 (A 8))
        (NC
          (NC (N1 (A 1)) vars)
          (N1 (nockToNoun ef)))
      where
        vars = foldr NC (N1 (A 0)) vfs

-- | The proposed new calling convention
copy :: Ord a => Exp a -> Nock
copy = copyToNock . toCopy

-- x. y. x
-- old: [8 [1 0] [1 8 [1 0] [1 0 30] 0 1] 0 1]
--      =+  0  =
