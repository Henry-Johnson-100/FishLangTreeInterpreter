module Util.String
  ( strip,
    onlyLiteral,
  )
where

import qualified Data.Char (isSpace)
import qualified Data.List (isPrefixOf, isSuffixOf)

strip :: String -> String
strip str =
  reverse $
    dropWhile Data.Char.isSpace $
      reverse $
        dropWhile Data.Char.isSpace str

onlyLiteral :: String -> String
onlyLiteral strs
  | "\"" `Data.List.isPrefixOf` strs = (onlyLiteral . tail) strs
  | "\"" `Data.List.isSuffixOf` strs = (onlyLiteral . init) strs
  | otherwise = strs