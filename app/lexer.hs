module Lexer (
    Token(..),
    tokenize,
    like,
    fromToken,
    filterLike,
    filterNotLike
) where

import Data.List
import Token.Util.Like
import Token.Util.String
import qualified Token.Bracket    as B
import qualified Token.Control    as C
import qualified Token.Data       as D
import qualified Token.Keyword    as K
import qualified Token.Operator   as O

data Token = Bracket B.Bracket | Control C.Control | Data D.Data | Keyword K.Keyword | Operator O.Operator deriving (Show,Read,Eq)

instance Like Token where
    like (Bracket a)       (Bracket b)  = True
    like (Control a)       (Control b)  = True
    like (Data a)          (Data b)     = True
    like (Keyword a)       (Keyword b)  = True
    like (Operator a)      (Operator b) = True
    like _                 _            = False
    notLike a              b            = not $ like a b


baseBracket :: Token -> B.Bracket
baseBracket (Bracket b) = b

baseControl :: Token -> C.Control
baseControl (Lexer.Control c) = c

baseData :: Token -> D.Data
baseData (Data d) = d

tokenFromData :: D.Data -> Token
tokenFromData d = Data d

baseKeyword :: Token -> K.Keyword
baseKeyword (Keyword k) = k

baseOperator :: Token -> O.Operator
baseOperator (Operator o) = o

filterLike :: Token -> [Token] -> [Token]
filterLike t ts = filter (\x -> x `like` t) ts

filterNotLike :: Token -> [Token] -> [Token]
filterNotLike t ts = filter (\x -> x `notLike` t) ts

fromToken :: Token -> String
fromToken (Bracket bracket)       = B.fromBracket bracket
fromToken (Lexer.Control control) = C.fromControl control
fromToken (Data d)                = D.fromData    d
fromToken (Keyword keyword)       = K.fromKeyword keyword
fromToken (Operator operator)     = O.fromOp      operator

readTokenFromWord :: String -> Token
readTokenFromWord str
    | elem str K.repr = Keyword       (K.readKeyword str)
    | elem str B.repr = Bracket       (B.readBracket str)
    | elem str C.repr = Lexer.Control (C.readControl str)
    | elem str O.repr = Operator      (O.readOp      str)
    | otherwise       = Data          (D.readData    str)


addSpaces :: String -> String
addSpaces str
    | null str = ""
    | isAnyReprInHeadGroup B.repr                                                                     = (padReprElemFromHeadGroup B.repr 1)      ++ (addSpaces $ dropReprElemFromHeadGroup B.repr str)
    | isAnyReprInHeadGroup D.punctRepr                                                                = (padReprElemFromHeadGroup D.punctRepr 1) ++ (addSpaces $ dropReprElemFromHeadGroup D.punctRepr str)
    | isAnyReprInHeadGroup O.repr                                                                     = case length (filterReprElemsInHeadGroup O.repr) == 1 of True  -> (padReprElemFromHeadGroup O.repr 1)                                         ++ (addSpaces $ dropReprElemFromHeadGroup O.repr str)
                                                                                                                                                                False -> (padEqual (getLongestStringFromList (filterReprElemsInHeadGroup O.repr)) 1) ++ (addSpaces $ drop (maximum (map (length) (filterReprElemsInHeadGroup O.repr))) str )
    | otherwise = (head str) : addSpaces (tail str)
    where
        headGroup :: String
        headGroup = take 3 str
        isAnyReprInHeadGroup :: [String] -> Bool
        isAnyReprInHeadGroup reprList = any (\reprElem -> isPrefixOf reprElem headGroup) reprList
        filterReprElemsInHeadGroup :: [String] -> [String]
        filterReprElemsInHeadGroup reprList = filter (\reprElem -> isPrefixOf reprElem headGroup) reprList
        getReprElemInHeadGroup :: [String] -> String
        getReprElemInHeadGroup reprList = head $ filterReprElemsInHeadGroup reprList
        padReprElemFromHeadGroup :: [String] -> Int -> String
        padReprElemFromHeadGroup reprList space = padEqual (getReprElemInHeadGroup reprList) space
        dropReprElemFromHeadGroup :: [String] -> String -> String
        dropReprElemFromHeadGroup reprList str = drop (length (getReprElemInHeadGroup reprList)) str
        getLongestStringFromList :: [String] -> String
        getLongestStringFromList strs = head $ filter (\x -> length x == maximum (map length strs)) strs


consolidateStringsIfPossible :: [Token] -> [Token]
consolidateStringsIfPossible [] = []
consolidateStringsIfPossible (t:ts)
    | t `like` (Data (D.Other "")) = consolidatedTokenDataList ++ consolidateStringsIfPossible (droppedTokenDataList)
    | otherwise                    = t : consolidateStringsIfPossible ts
    where
        droppedTokenDataList = dropWhile (like (Data (D.Other ""))) (t:ts)
        consolidatedTokenDataList = map (tokenFromData) $ filter ((D.Other " ")/=) $ D.consolidateStrings $ intersperse (D.Other " ") $ map (baseData) (takeWhile (like (Data (D.Other ""))) (t:ts))


tokenize :: String -> [Token]
tokenize strs = consolidateStringsIfPossible $ map (readTokenFromWord) $ words $ addSpaces strs