

fish to_bool

  >(x)>

  <(
    fin
    >(x)>
    >(True)>
    >(False)>
  )<



fish or

  >(x)>
  >(y)>

  <(
    fin
    >(x)>
    >(True)>
    >(to_bool >(y)>)>
  )<



fish and

  >(x)>
  >(y)>

  <(
    fin
    >(x)>
    >(to_bool >(y)>)>
    >(False)>
  )<



fish not

  >(x)>

  <(
    fin
    >(to_bool >(x)>)>
    >(False)>
    >(True)>
  )<






fish main

  >(main_arg)>
  >(
    _x_ <(
    not >(main_arg)>
    )<
  )>
  >(
    __x__ <(
    not >(_x_)>
    )<
  )>

  <(
    fin
    >(__x__)>
    >("That's right")>
    >("That's wrong")>
  )<

fish increment
  >(n)>
  <(+ >(n)> >(1)>)<


fish factorial

  >(n)>
  >(
      fish fact_st

        >(n)>
        >(prod)>
        <(
          fin
            >(<= >(n)> >(0)>)>
            >(prod)>
            >(
              fact_st >(- >(n)> >(1)>)> >(* >(prod)> >(n)>)>
            )>
        )<
  )>

  <(fact_st >(n)> >(1)>)<

/*Here is the main execution*/
<(
  True
)<