module Token.Operator
  ( Operator (..),
    readOp,
    fromOp,
    repr,
    spacingRepr,
  )
where

data Operator
  = Eq
  | NEq
  | Gt
  | Lt
  | Add
  | Sub
  | Mult
  | Div
  | Mod
  | GtEq
  | LtEq
  deriving (Show, Read, Eq)

repr :: [String]
repr = ["==", "/=", "+", "-", "*", "/", "%", ">=", "<=", "<", ">"]

spacingRepr :: [String]
spacingRepr = ["==", "/=", "+", "*", "/", "%", ">=", "<=", "<", ">"]

readOp :: String -> Operator
readOp "==" = Eq
readOp "/=" = NEq
readOp ">" = Gt
readOp "<" = Lt
readOp "+" = Add
readOp "-" = Sub
readOp "*" = Mult
readOp "/" = Div
readOp "%" = Mod
readOp ">=" = GtEq
readOp "<=" = LtEq

fromOp :: Operator -> String
fromOp Eq = "=="
fromOp NEq = "/="
fromOp Gt = ">"
fromOp Lt = "<"
fromOp Add = "+"
fromOp Sub = "-"
fromOp Mult = "*"
fromOp Div = "/"
fromOp Mod = "%"
fromOp GtEq = ">="
fromOp LtEq = "<="