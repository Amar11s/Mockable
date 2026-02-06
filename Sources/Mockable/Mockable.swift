@attached(peer, names: prefixed(Mock))
public macro Mockable() =
    #externalMacro(module: "MockableMacros", type: "MockableMacro")
