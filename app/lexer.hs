module Lexer (
    Token(..),
    tokenize,
    fromToken
) where

import Data.List
import Data.Char (isSpace)
import Token.Util.Like
import Token.Util.String
import Token.Util.EagerCollapsible
import Token.Util.NestedCollapsible
import Token.Bracket    as B
import Token.Control    as C
import Token.Data       as D
import Token.Keyword    as K
import Token.Operator   as O

data Token = Bracket Bracket | Control Control | Data Data | Keyword Keyword | Operator Operator deriving (Show,Read,Eq)


data TokenUnit = TokenUnit {
    token :: Token,
    unitLine  :: Int
} deriving (Show, Read, Eq)


data Packet a = Packet {
    members :: [a],
    packetLine :: Int
} deriving (Show, Eq)


instance Like Token where
    like (Bracket a)       (Bracket b)  = True
    like (Control a)       (Control b)  = True
    like (Data a)          (Data b)     = True
    like (Keyword a)       (Keyword b)  = True
    like (Operator a)      (Operator b) = True
    like _                 _            = False
    notLike a              b            = not $ like a b


instance Like TokenUnit where
    like x y = (token x) `like` (token y)
    notLike x y = not $ like x y


instance Functor Packet where
    fmap f sp = Packet (fmap f (members sp)) (packetLine sp)


tokenPacketToUnit :: Packet Token -> [TokenUnit]
tokenPacketToUnit tp = map (\t -> (TokenUnit t (packetLine tp))) (members tp)


baseData :: Token -> Data
baseData (Data d) = d


baseDataString :: Token -> String
baseDataString t = D.fromData $ baseData t


fromToken :: Token -> String
fromToken (Bracket bracket)       = B.fromBracket bracket
fromToken (Lexer.Control control) = C.fromControl control
fromToken (Data d)                = D.fromData    d
fromToken (Keyword keyword)       = K.fromKeyword keyword
fromToken (Operator operator)     = O.fromOp      operator


fromTokenUnit :: TokenUnit -> String
fromTokenUnit tu = fromToken $ token tu


readToken :: String -> Token
readToken str
    | elem str K.repr = Keyword       (K.readKeyword str)
    | elem str B.repr = Bracket       (B.readBracket str)
    | elem str C.repr = Lexer.Control (C.readControl str)
    | elem str O.repr = Operator      (O.readOp      str)
    | otherwise       = Data          (D.readData    str)


addSpaces :: String -> String
addSpaces str
    | null str = ""
    | isAnyReprInHeadGroup B.repr     = (padReprElemFromHeadGroup B.repr 1)     ++ (addSpaces $ dropReprElemFromHeadGroup B.repr str)
    | isAnyReprInHeadGroup D.miscRepr = (padReprElemFromHeadGroup D.miscRepr 1) ++ (addSpaces $ dropReprElemFromHeadGroup D.miscRepr str)
    | isAnyReprInHeadGroup O.repr     = case length (filterReprElemsInHeadGroup O.repr) == 1 of True  -> (padReprElemFromHeadGroup O.repr 1)                                         ++ (addSpaces $ dropReprElemFromHeadGroup O.repr str)
                                                                                                False -> (padEqual (getLongestStringFromList (filterReprElemsInHeadGroup O.repr)) 1) ++ (addSpaces $ drop (maximum (map (length) (filterReprElemsInHeadGroup O.repr))) str )
    | otherwise = (head str) : addSpaces (tail str)
    where
        headGroup :: String
        headGroup = take 5 str
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


tokenIsStringPrefix :: Token -> Bool
tokenIsStringPrefix (Data (D.String a)) = ((isPrefixOf "\"" a) && (not $ isSuffixOf "\"" a)) || (length a == 1)
tokenIsStringPrefix _                   = False


tokenIsStringSuffix :: Token -> Bool
tokenIsStringSuffix (Data (D.String a)) = ((isSuffixOf "\"" a) && (not $ isPrefixOf "\"" a)) || (length a == 1)
tokenIsStringSuffix _          = False


tokenIsCommentPrefix :: Token -> Bool
tokenIsCommentPrefix (Data (D.Comment a)) = isPrefixOf "/*" a
tokenIsCommentPrefix _         = False


tokenIsCommentSuffix :: Token -> Bool
tokenIsCommentSuffix (Data (D.Comment a)) = isSuffixOf "*/" a
tokenIsCommentSuffix _         = False


stringIsCommentPrefix :: String -> Bool
stringIsCommentPrefix a = isPrefixOf "/*" a


stringIsCommentSuffix :: String -> Bool
stringIsCommentSuffix a = isSuffixOf "*/" a


consolidateEagerCollapsibleTokens :: [Token] -> [Token]
consolidateEagerCollapsibleTokens [] = []
consolidateEagerCollapsibleTokens (t:ts)
    | tokenIsStringPrefix t && isEagerCollapsible tokenIsStringPrefix tokenIsStringSuffix (t:ts) = (mapToConsolidatedData (Data (D.String "")) (t:ts))  ++ consolidateEagerCollapsibleTokens (dropBetween (tokenIsStringPrefix)  (tokenIsStringSuffix)  (t:ts))
    | otherwise                                                                                  = t : consolidateEagerCollapsibleTokens ts
    where
        mapTakeBetween :: Token -> [Token] -> [Token]
        mapTakeBetween emptyTokenDataType xs = map (\t -> (constructDataToken emptyTokenDataType) (D.fromData (baseData t))) $ takeBetween (isDataTypePrefix emptyTokenDataType) (isDataTypeSuffix emptyTokenDataType) xs
        mapToConsolidatedData :: Token -> [Token] -> [Token]
        mapToConsolidatedData emptyTokenDataType xs = (constructDataToken emptyTokenDataType) (concat (map (\t -> D.fromData (baseData t)) (mapTakeBetween emptyTokenDataType xs))) : []
        isDataTypePrefix :: Token -> Token -> Bool
        isDataTypePrefix (Data (D.String  _)) = tokenIsStringPrefix
        isDataTypeSuffix :: Token -> Token -> Bool
        isDataTypeSuffix (Data (D.String  _)) = tokenIsStringSuffix
        constructDataToken :: Token -> String -> Token
        constructDataToken (Data (D.String  _)) str = (Data (D.String str))


-- mapOnTokenInLine :: (Token -> Token) -> [TokenPacket] -> [TokenPacket]
-- mapOnTokenInLine _ [] = []
-- mapOnTokenInLine f (t:tils) = (TokenPacket (f (token t)) (packetLine t)) : mapOnTokenInLine f tils


-- consolidateEagerCollapsibleTokenInLines :: [TokenPacket] -> [TokenPacket]
-- consolidateEagerCollapsibleTokenInLines [] = []
-- consolidateEagerCollapsibleTokenInLines (t:ts)
--     | tokenIsStringPrefix (token t) && isEagerCollapsible (\t' -> tokenIsStringPrefix (token t'))  (\t' -> tokenIsStringSuffix (token t'))  (t:ts) = (mapToConsolidatedDataString (t:ts))  ++ consolidateEagerCollapsibleTokenInLines (dropBetween (\t' -> tokenIsStringPrefix (token t'))  (\t' -> tokenIsStringSuffix (token t'))  (t:ts))
--     | otherwise                                                                                                                     = t : consolidateEagerCollapsibleTokenInLines ts
--     where
--         mapTakeBetween :: [TokenPacket] -> [TokenPacket]
--         mapTakeBetween xs = mapOnTokenInLine (\t -> (Data (D.String (baseDataString t)))) $ takeBetween (\t -> tokenIsStringPrefix (token t)) (\t -> tokenIsStringSuffix (token t)) xs
--         mapToConsolidatedDataString :: [TokenPacket] -> [TokenPacket]
--         mapToConsolidatedDataString xs = (TokenPacket (Data (D.String (concat (map (\til -> baseDataString (token til)) (mapTakeBetween xs))))) (packetLine (head xs))) : []


-- consolidateNestedCollapsibleTokens :: [Token] -> [Token]
-- consolidateNestedCollapsibleTokens [] = []
-- consolidateNestedCollapsibleTokens ts 
--     | all null (unwrapPartition part) = ts
--     | otherwise =  (flattenedFstSnd part) ++ (consolidateNestedCollapsibleTokens (partThd part))
--     where
--         part = breakByNest (NCCase isCommentPrefix isCommentSuffix) ts
--         flattenedFstSnd part' = (partFst part') ++ ((Data (D.Comment (concat (map (fromToken) (partSnd part'))))) : [])


-- consolidateNestedCollapsibleTokenInLines :: [TokenPacket] -> [TokenPacket]
-- consolidateNestedCollapsibleTokenInLines [] = []
-- consolidateNestedCollapsibleTokenInLines ts 
--     | all null (unwrapPartition part) = ts
--     | otherwise =  (flattenedFstSnd part) ++ (consolidateNestedCollapsibleTokenInLines (partThd part))
--     where
--         part = breakByNest (NCCase (\t -> isCommentPrefix (token t)) (\t -> isCommentSuffix (token t))) ts
--         flattenedFstSnd part' = (partFst part') ++ ((TokenPacket (Data (D.Comment (concat (map (\til -> fromToken (token til)) (partSnd part'))))) 0) : [])

-- **************************************
-- ignoreComments :: [TokenPacket] -> [TokenPacket]
-- ignoreComments [] = []
-- ignoreComments ts = filter (\t -> not (tokenPacketIsComment t)) ts where
--     tokenPacketIsComment :: TokenPacket -> Bool
--     tokenPacketIsComment t = t `like` (TokenPacket (Data (D.Other "")) 0) && (baseData t) `like` (D.Comment "")

wordsPreserveStringSpacing :: String -> [String]
wordsPreserveStringSpacing str = wordsPreserveStringSpacingScan [] str where
    wordsPreserveStringSpacingScan :: [String] -> String -> [String]
    wordsPreserveStringSpacingScan strs "" = strs
    wordsPreserveStringSpacingScan strs (s:str)
        | s == '"' = wordsPreserveStringSpacingScan (strs ++ ((buildPreservedString str) : [])) (dropInfix (buildPreservedString str) (s:str))
        | isSpace s = wordsPreserveStringSpacingScan strs str
        | otherwise = wordsPreserveStringSpacingScan (strs ++ ((buildWord (s:str)) : [])) (dropInfix (buildWord (s:str)) (s:str))
        where
            buildPreservedString :: String -> String
            buildPreservedString str = "\"" ++ (takeWhile ((/=) '\"') str ) ++ "\""
            buildWord            :: String -> String
            buildWord str = (takeWhile (\s -> not (isSpace s)) str)


-- -- tokenize :: String -> [Token]
-- -- tokenize strs = ignoreComments $ consolidateNestedCollapsibleTokens $ consolidateEagerCollapsibleTokens $ map (readToken) $ wordsPreserveStringSpacing $ addSpaces strs


prepareRawString :: String -> [Packet String]
prepareRawString "" = []
prepareRawString strs = zippedLineNumbersToStringPackets $ mapPreserveLn wordsPreserveStringSpacing $ mapPreserveLn addSpaces $ zipNumbersToLines
    where
        linesStrs = reverse $ dropWhile null $ reverse $ lines strs
        --zipNumbersToLines :: [([String], Int)]
        zipNumbersToLines = zip (linesStrs) ([1..((length linesStrs) + 1)])
        zippedLineNumbersToStringPackets :: [([String], Int)] -> [Packet String]
        zippedLineNumbersToStringPackets zs = map (\z -> Packet (fst z) (snd z)) zs
        mapPreserveLn :: (a -> b) -> [(a,Int)] -> [(b,Int)]
        mapPreserveLn f xs = map (\(first,second) -> (f first, second)) xs


tokenize :: String -> [Packet Token]
tokenize strs = map (\ps -> Packet (consolidateEagerCollapsibleTokens (members ps)) (packetLine ps)) $ filterEmptyPackets $ tokenizePreparedStringLines $ prepareRawString strs where
    filterEmptyPackets :: [Packet a] -> [Packet a]
    filterEmptyPackets pss = filter (\ps -> not (null (members ps))) pss
    tokenizePreparedStringLines :: [Packet String] -> [Packet Token]
    tokenizePreparedStringLines [] = []
    tokenizePreparedStringLines (ps:pss)
            | hasCommentPrefix ps && hasCommentSuffix ps = (mapStringPToTokenPIgnoreSameLineComments ps) : tokenizePreparedStringLines pss
            | hasCommentPrefix ps                        = (mapStringPToTokenPTakeUntilComment ps)       : tokenizePreparedStringLines (dropWhile (\ps' -> not (any (\ps'' -> stringIsCommentSuffix ps'') (members ps'))) pss)
            | hasCommentSuffix ps                        = (mapStringPToTokenPDropThroughComment ps)     : tokenizePreparedStringLines pss
            | otherwise                                  = (fmap readToken ps)                           : tokenizePreparedStringLines pss
            where
                hasCommentPrefix :: Packet String -> Bool
                hasCommentPrefix ps' = any (\ps'' -> stringIsCommentPrefix ps'') (members ps')
                hasCommentSuffix :: Packet String -> Bool
                hasCommentSuffix ps' = any (\ps'' -> stringIsCommentSuffix ps'') (members ps')
                mapStringPToTokenPIgnoreSameLineComments :: Packet String -> Packet Token
                mapStringPToTokenPIgnoreSameLineComments ps' = (fmap readToken (Packet ((takeWhile (\x -> not (stringIsCommentPrefix x)) (members ps')) ++ (tail' (dropWhile (\x -> not (stringIsCommentSuffix x)) (members ps')))) (packetLine ps')))
                mapStringPToTokenPTakeUntilComment :: Packet String -> Packet Token
                mapStringPToTokenPTakeUntilComment ps' = (fmap readToken (Packet (takeWhile (\x -> not (stringIsCommentPrefix x)) (members ps')) (packetLine ps')))
                mapStringPToTokenPDropThroughComment :: Packet String -> Packet Token
                mapStringPToTokenPDropThroughComment ps' = (fmap readToken (Packet (tail' (dropWhile (\x -> not (stringIsCommentSuffix x)) (members ps'))) (packetLine ps')))
                tail' :: [a] -> [a]
                tail' [] = []
                tail' (x:xs) = xs





        
        -- currentToken :: StringPacket -> Token
        -- currentToken ps' = readToken $ fst ps'
        -- currentTokenIsComment :: StringPacket -> Bool
        -- currentTokenIsComment ps' = (currentToken ps') `like` (Data (Comment ""))
        -- tokenizePreparedStringLines' :: [StringPacket] -> [TokenPacket] -> Bool -> [TokenPacket]
        -- tokenizePreparedStringLines' [] tps _ = tps
        -- tokenizePreparedStringLines' (ps:pss') tps True = if currentTokenIsComment ps 
        --                                                         then tokenizePreparedStringLines' pss' tps False 
        --                                                         else tokenizePreparedStringLines' pss' tps True
        -- tokenizePreparedStringLines' (ps:pss') tps pass
        --     | currentTokenIsComment ps = tokenizePreparedStringLines' pss' tps True
        --     where

        --         addTokenPacketToList :: TokenPacket -> [TokenPacket] -> [TokenPacket]
        --         addTokenPacketToList tp' tps' = map (\x -> if (packetLine tp') == (packetLine x) then (TokenPacket ((tokens tp') ++ (tokens x)) (packetLine x)) else x) tps'