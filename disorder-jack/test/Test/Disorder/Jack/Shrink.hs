{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TemplateHaskell #-}
module Test.Disorder.Jack.Shrink where

import           Control.Applicative (Applicative(..), Alternative(..))
import           Control.Comonad (duplicate)
import           Control.Monad (Monad(..))

import           Data.Bool (Bool(..), (&&))
import           Data.Foldable (foldl)
import           Data.Function (($), (.))
import           Data.Functor (Functor(..), (<$>))
import           Data.Int (Int)
import qualified Data.List as List
import           Data.Maybe (Maybe(..))
import           Data.Monoid ((<>))
import           Data.Ord (Ord(..))
import           Data.Text (Text)
import qualified Data.Text as T

import           Disorder.Jack.Combinators
import           Disorder.Jack.Core
import           Disorder.Jack.Property
import           Disorder.Jack.Tree

import           Prelude (Num(..))

import           System.IO (IO)

import qualified Test.QuickCheck as QC
import qualified Test.QuickCheck.Property as QC

import           Text.Show (Show)
import           Text.Show.Pretty (ppShow)


data Exp =
    Var !Text
  | Con !Int
  | Lam !Text !Exp
  | App !Exp !Exp
    deriving (Show)

exp :: Int -> Jack Exp
exp n =
  let
    text =
      T.pack <$> arbitrary

    exp0 = [
        Con <$> sizedIntegral
      , Var <$> text
      ]

    expN = [
        Lam <$> text <*> exp (n-1)
      , App <$> exp (n-1) <*> exp (n-1)
      ]

    shrink = \case
      Lam _ x ->
        [x]
      App x y ->
        [x, y]
      _ ->
        []
  in
    reshrink shrink $
      oneof (exp0 <> if n > 0 then expN else [])

noAppCon10 :: Exp -> Bool
noAppCon10 = \case
  Con _ ->
    True
  Var _ ->
    True
  Lam _ x ->
    noAppCon10 x
  App _ (Con 10) ->
    False
  App x1 x2 ->
    noAppCon10 x1 && noAppCon10 x2

smallestFailure :: (a -> Bool) -> Tree a -> Maybe a
smallestFailure f (Node x xs) =
  if f x then
    Nothing
  else
    foldl (<|>) empty (fmap (smallestFailure f) xs) <|> Just x

prop_jack :: Property
prop_jack =
  gamble (mapTree duplicate . list $ sized exp) $ \xs ->
    case smallestFailure (List.all noAppCon10) xs of
      Nothing ->
        property QC.succeeded
      -- The tree must be organised such that smallest fail is found by greedy
      -- traversal with a predicate.
      Just [App (Con 0) (Con 10)] ->
        property QC.succeeded
      Just x ->
        QC.counterexample "" .
        QC.counterexample "Greedy traversal with predicate did not yield the minimal shrink." .
        QC.counterexample "" .
        QC.counterexample "=== Minimal ===" .
        QC.counterexample (ppShow [App (Con 0) (Con 10)]) .
        QC.counterexample "=== Actual ===" .
        QC.counterexample (ppShow x) $
        property QC.failed

return []
tests :: IO Bool
tests =
  $(QC.forAllProperties) . QC.quickCheckWithResult $
    QC.stdArgs { QC.maxSuccess = 100 }
