{-# LANGUAGE MagicHash #-}

module SyntaxTree
  ( generateSyntaxTree,
    generateModuleTree,
    SyntaxTree,
    TreeIO (..),
    SyntaxUnit (..),
  )
where

import Data.List
import Data.Maybe (fromJust, isNothing)
import Exception.Base
import Lexer
import Token.Bracket
  ( BracketTerminal (Close, Open),
    ScopeType (Return, Send),
  )
import Token.Data
import Token.Keyword
import Token.Util.EagerCollapsible (dropInfix)
import Token.Util.Like
import Token.Util.NestedCollapsible
  ( NCCase (NCCase),
    TriplePartition (..),
    breakByNest,
    groupAllTopLevelNestedCollapsibles,
    groupByPartition,
    hasNestedCollapsible,
    isCompleteNestedCollapsible,
    nestedCollapsibleIsPrefixOf,
    takeNestWhileComplete,
    takeWhileList,
    unwrapPartition,
  )
import Token.Util.Tree

data SyntaxUnit = SyntaxUnit
  { token :: Token,
    line :: Int,
    context :: ScopeType
  }
  deriving (Show, Eq)

genericSyntaxUnit :: Token -> SyntaxUnit
genericSyntaxUnit t = SyntaxUnit t 0 Return

setContext :: SyntaxUnit -> ScopeType -> SyntaxUnit
setContext su st = su {context = st}

type SyntaxTree = Tree SyntaxUnit

type SyntaxPartition = TriplePartition SyntaxUnit

generateModuleTree :: String -> [TokenUnit] -> SyntaxTree
generateModuleTree name = flip nameModuleTree name . generateSyntaxTree

nameModuleTree :: SyntaxTree -> String -> SyntaxTree
nameModuleTree tr str = mutateTreeNode tr (\_ -> genericSyntaxUnit (Data (Id str)))

generateSyntaxTree :: [TokenUnit] -> SyntaxTree
generateSyntaxTree [] = Empty
generateSyntaxTree tus =
  (declarationErrorCheck# . reContextualizeSchoolMethods) $
    tree (genericSyntaxUnit (Data (Id "main")))
      -<= concatMap syntaxPartitionTree ((getSyntaxPartitions . scanTokensToSyntaxes) tus)

bracketNestCase :: NCCase SyntaxUnit
bracketNestCase = NCCase (\x -> token x `elem` [Bracket Send Open, Bracket Return Open]) (\x -> token x `elem` [Bracket Send Close, Bracket Return Close])

takeBracketNestedCollapsibleExcludingReturn :: [SyntaxUnit] -> [SyntaxUnit]
takeBracketNestedCollapsibleExcludingReturn [] = []
takeBracketNestedCollapsibleExcludingReturn (tu : tus)
  | null (partSnd part) = []
  | (getTokenBracketScopeType . token . head . partSnd) part == Return = []
  | otherwise = partFstSnd ++ takeBracketNestedCollapsibleExcludingReturn (partThd part)
  where
    part = breakByNest bracketNestCase (tu : tus)
    partFstSnd = partFst part ++ partSnd part

takeBracketNestedCollapsibleIncludingReturn :: [SyntaxUnit] -> [SyntaxUnit]
takeBracketNestedCollapsibleIncludingReturn [] = []
takeBracketNestedCollapsibleIncludingReturn (tu : tus)
  | null (partSnd part) = []
  | getTokenBracketScopeType (token (head (partSnd part))) == Return = partFstSnd
  | otherwise = partFstSnd ++ takeBracketNestedCollapsibleIncludingReturn (partThd part)
  where
    part = breakByNest bracketNestCase (tu : tus)
    partFstSnd = partFst part ++ partSnd part

scanTokensToSyntaxes :: [TokenUnit] -> [SyntaxUnit]
scanTokensToSyntaxes [] = []
scanTokensToSyntaxes tus = zipWith tokenUnitToSyntaxUnit tus (scanScopeTypes tus)
  where
    tokenUnitToSyntaxUnit :: TokenUnit -> ScopeType -> SyntaxUnit
    tokenUnitToSyntaxUnit tu = SyntaxUnit (unit tu) (unitLine tu)
    scanScopeTypes :: [TokenUnit] -> [ScopeType]
    scanScopeTypes [] = []
    scanScopeTypes tus = scanl getScanScopeType Return tus
      where
        getScanScopeType :: ScopeType -> TokenUnit -> ScopeType
        getScanScopeType _ (PacketUnit (Bracket Send Open) _) = Send
        getScanScopeType _ (PacketUnit (Bracket Return Open) _) = Return
        getScanScopeType st _ = st

getSyntaxPartitions :: [SyntaxUnit] -> [SyntaxPartition]
getSyntaxPartitions [] = []
getSyntaxPartitions tus = map syntaxPartitionFromChunk (groupSyntaxChunks tus)
  where
    syntaxPartitionFromChunk :: [SyntaxUnit] -> SyntaxPartition
    syntaxPartitionFromChunk [] = TriplePartition [] [] []
    syntaxPartitionFromChunk tus = TriplePartition w a r
      where
        w = takeWhileList (not . nestedCollapsibleIsPrefixOf bracketNestCase) tus
        a = takeBracketNestedCollapsibleExcludingReturn (dropInfix w tus)
        r = dropInfix (w ++ a) tus
    groupSyntaxChunks :: [SyntaxUnit] -> [[SyntaxUnit]]
    groupSyntaxChunks [] = []
    groupSyntaxChunks tus' = (fst . spanOnSyntaxChunk) tus' : (groupSyntaxChunks . snd . spanOnSyntaxChunk) tus'
      where
        spanOnSyntaxChunk :: [SyntaxUnit] -> ([SyntaxUnit], [SyntaxUnit])
        spanOnSyntaxChunk [] = ([], [])
        spanOnSyntaxChunk tus = (takenThroughReturn, dropInfix takenThroughReturn tus)
          where
            takenThroughReturn = takeBracketNestedCollapsibleIncludingReturn tus

-- | Receptacle for all possible pattern matches of a TriplePartition when making a tree
syntaxPartitionTree :: SyntaxPartition -> [SyntaxTree]
syntaxPartitionTree (TriplePartition [] [] []) = []
syntaxPartitionTree (TriplePartition x [] []) = treeOnlyNonTerminals (TriplePartition x [] [])
syntaxPartitionTree (TriplePartition [] y []) = treeConcurrentBracketGroups y
syntaxPartitionTree (TriplePartition [] [] z) = treeOnlyValue (TriplePartition [] [] z)
syntaxPartitionTree (TriplePartition x [] z) = treeNoArgs (TriplePartition x [] z)
syntaxPartitionTree (TriplePartition x y []) = treeFunctionCall (TriplePartition x y [])
syntaxPartitionTree (TriplePartition [] y z) = treeAnonFunction (TriplePartition [] y z)
syntaxPartitionTree (TriplePartition x y z) = treeFullDeclaration (TriplePartition x y z)

treeOnlyNonTerminals :: SyntaxPartition -> [SyntaxTree]
treeOnlyNonTerminals (TriplePartition x [] []) = [serialTree x]

treeOnlyValue :: SyntaxPartition -> [SyntaxTree]
treeOnlyValue (TriplePartition [] [] z) = treeSingleBracketGroup z

treeNoArgs :: SyntaxPartition -> [SyntaxTree]
treeNoArgs (TriplePartition x [] z) = [declaration -<= funcReturn]
  where
    declaration = serialTree x
    funcReturn = treeSingleBracketGroup z

treeFunctionCall :: SyntaxPartition -> [SyntaxTree]
treeFunctionCall (TriplePartition x y []) = [funcId -<= funcArgs]
  where
    funcId = serialTree x
    funcArgs = treeConcurrentBracketGroups y

treeAnonFunction :: SyntaxPartition -> [SyntaxTree]
treeAnonFunction (TriplePartition [] y z) = args ++ funcReturn
  where
    funcReturn = treeSingleBracketGroup z
    args = treeConcurrentBracketGroups y

treeFullDeclaration :: SyntaxPartition -> [SyntaxTree]
treeFullDeclaration (TriplePartition x y z) = [(declaration -<= args) -<= funcReturn]
  where
    declaration = serialTree x
    funcReturn = treeSingleBracketGroup z
    args = treeConcurrentBracketGroups y

treeConcurrentBracketGroups :: [SyntaxUnit] -> [SyntaxTree]
treeConcurrentBracketGroups tus = concatMap treeSingleBracketGroup (groupBrackets tus)
  where
    groupBrackets :: [SyntaxUnit] -> [[SyntaxUnit]]
    groupBrackets [] = [[]]
    groupBrackets tus = groupTopLevelAndErrorCheck --this is where free tokens get removed
      where
        groupTopLevelAndErrorCheck = map (partSnd . partitionHasFreeTokenErrorCheck#) (groupByPartition bracketNestCase tus)
        partitionHasFreeTokenErrorCheck# :: SyntaxPartition -> SyntaxPartition
        partitionHasFreeTokenErrorCheck# sp
          | (not . null . partFst) sp = freeTokenError# (partFst sp)
          | otherwise = sp
          where
            freeTokenError# :: [SyntaxUnit] -> SyntaxPartition --Never returns anything, therefore, this function signature is useless at best or misleading at worst
            freeTokenError# sus
              | (keywordTokenIsDeclarationRequiringId . token . head) sus = raiseFreeTokenError# getTokenLines ("Free tokens in ambiguous scope, \'" ++ getTokenStrings ++ "\' Is there a missing return fish before this declaration?") Fatal
              | otherwise = raiseFreeTokenError# getTokenLines ("Free token(s) in ambiguous scope, \'" ++ getTokenStrings ++ "\' are they meant to be in a fish?") NonFatal
              where
                getTokenLines = map line sus
                getTokenStrings = (intercalate ", " . map (fromToken . token)) sus
                raiseFreeTokenError# ln str sev = raiseError $ newException FreeTokensInForeignScope ln str sev

treeSingleBracketGroup :: [SyntaxUnit] -> [SyntaxTree]
treeSingleBracketGroup [] = [(tree . genericSyntaxUnit) (Data Null)]
treeSingleBracketGroup xs
  | isCompleteNestedCollapsible bracketNestCase xs = treeSingleBracketGroup (takeNestWhileComplete bracketNestCase xs)
  | hasNestedCollapsible bracketNestCase xs = concatMap syntaxPartitionTree $ getSyntaxPartitions xs
  | otherwise = [serialTree xs]

reContextualizeSchoolMethods :: SyntaxTree -> SyntaxTree
reContextualizeSchoolMethods Empty = Empty
reContextualizeSchoolMethods st
  | null (lookupOn st (\x -> (token . fromJust . treeNode) x == Keyword School)) = st
  | (token . fromJust . treeNode) st /= Keyword School = reTree st -<= childMap reContextualizeSchoolMethods st
  | otherwise = reTree st -<= map reContextualizeSchoolMethods reContextualizedChildren
  where
    reContextualizedChildren :: [SyntaxTree]
    reContextualizedChildren = fst breakOnSendReturn ++ map (\x -> mutateTreeNode x (`setContext` Return)) (snd breakOnSendReturn)
    breakOnSendReturn = span (\x -> Send == (context . fromJust . treeNode) x) (treeChildren st)

declarationErrorCheck# :: SyntaxTree -> SyntaxTree
declarationErrorCheck# = readTreeForError# (maybeOnTreeNode False (keywordTokenIsDeclarationRequiringId . token)) (declarationHasIdToken# . declarationIdHasNoChildren#)
  where
    declarationHasIdToken# tr
      | nthChildMeetsCondition 0 (maybeOnTreeNode False (dataTokenIsId . token)) tr = tr
      | otherwise = raiseError $ newException DeclarationMissingId [getSyntaxAttributeFromTree line tr] "Declaration missing identification." Fatal
    declarationIdHasNoChildren# tr
      | nthChildMeetsCondition 0 (not . any (Empty /=) . treeChildren) tr = tr
      | otherwise =
        raiseError $
          newException
            FreeTokensInForeignScope
            (map (getSyntaxAttributeFromTree line) (allChildrenOfDeclarationId tr))
            ( "Free tokens, \'"
                ++ intercalate ", " (map (fromToken . getSyntaxAttributeFromTree token) (allChildrenOfDeclarationId tr))
                ++ "\' after a declaration Id should not be included"
            )
            NonFatal
      where
        allChildrenOfDeclarationId = concat . childrenOfChildren . head . treeChildren

nthChildMeetsCondition :: Int -> (SyntaxTree -> Bool) -> SyntaxTree -> Bool
nthChildMeetsCondition n f st
  | n < 0 = nthChildMeetsCondition ((length . treeChildren) st + n) f st
  | n > ((length . treeChildren) st - 1) = False
  | otherwise = (f . (!! n) . treeChildren) st

getSyntaxAttributeFromTree :: (SyntaxUnit -> a) -> SyntaxTree -> a
getSyntaxAttributeFromTree attr = maybeOnTreeNode ((attr . genericSyntaxUnit) (Data Null)) attr

readTreeForError# :: (SyntaxTree -> Bool) -> (SyntaxTree -> SyntaxTree) -> SyntaxTree -> SyntaxTree
readTreeForError# _ _ Empty = Empty
readTreeForError# stopOn readF tr
  | stopOn tr = (reTree . readF) tr -<= map (readTreeForError# stopOn readF) (treeChildren tr)
  | otherwise = reTree tr -<= map (readTreeForError# stopOn readF) (treeChildren tr)