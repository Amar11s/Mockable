import SwiftSyntax
import SwiftSyntaxMacros
import Foundation

public struct MockableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            return []
        }

        let protocolName = protocolDecl.name.text
        let mockName = "Mock\(protocolName)"

        var generatedMembers: [String] = []
        var givenCases: [String] = []
        var verifyCases: [String] = []
        var methodEnumCases: [String] = []
        var helperFunctions: [String] = []

        var verifyMethodCases: [String] = []
        var verifyHelperFunctions: [String] = []

        for member in protocolDecl.memberBlock.members {

            // -------- FUNCTIONS --------
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {

                let baseName = funcDecl.name.text
                let signature = funcDecl.signature
                let parameters = signature.parameterClause.parameters

                let paramNames: [String] = parameters.compactMap {
                    $0.firstName.text
                }

                let overloadSuffix = paramNames.isEmpty
                    ? ""
                    : "_" + paramNames.joined(separator: "_")

                let functionName = baseName + overloadSuffix

                let returnType = signature.returnClause?.type.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                generatedMembers.append("var \(functionName)CallCount = 0")

                if let returnType = returnType {

                    if parameters.isEmpty {

                        methodEnumCases.append("case \(functionName)(returnValue: \(returnType))")
                        methodEnumCases.append("case \(functionName)_invocation")

                        helperFunctions.append("""
                        static func \(baseName)(willReturn: \(returnType)) -> Method {
                            .\(functionName)(returnValue: willReturn)
                        }
                        """)

                        verifyMethodCases.append("case \(functionName)")

                        verifyHelperFunctions.append("""
                        static func \(baseName)() -> VerifyMethod {
                            .\(functionName)
                        }
                        """)

                        generatedMembers.append("""
                        struct \(functionName)Stub {
                            let returnValue: \(returnType)
                        }
                        """)

                        generatedMembers.append("var \(functionName)Stubs: [\(functionName)Stub] = []")

                        generatedMembers.append("""
                        func \(baseName)\(signature.description) {
                            \(functionName)CallCount += 1
                            invocations.append(.\(functionName)_invocation)

                            if let stub = \(functionName)Stubs.first {
                                return stub.returnValue
                            }
                            fatalError("No stub for \(functionName)")
                        }
                        """)

                        givenCases.append("""
                        case .\(functionName)(let returnValue):
                            \(functionName)Stubs.append(\(functionName)Stub(returnValue: returnValue))
                        """)

                        verifyCases.append("""
                        case .\(functionName):
                            actual = invocations.filter {
                                if case .\(functionName)_invocation = $0 { return true }
                                return false
                            }.count
                        """)

                    } else {

                        let param = parameters.first!
                        let paramName = param.firstName.text
                        let paramType = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)

                        methodEnumCases.append("""
                        case \(functionName)(\(paramName): Parameter<\(paramType)>, returnValue: \(returnType))
                        """)
                        methodEnumCases.append("case \(functionName)_invocation(\(paramName): \(paramType))")

                        helperFunctions.append("""
                        static func \(baseName)(\(paramName): Parameter<\(paramType)>, willReturn: \(returnType)) -> Method {
                            .\(functionName)(\(paramName): \(paramName), returnValue: willReturn)
                        }
                        """)

                        verifyMethodCases.append("case \(functionName)(\(paramName): Parameter<\(paramType)>)")

                        verifyHelperFunctions.append("""
                        static func \(baseName)(\(paramName): Parameter<\(paramType)>) -> VerifyMethod {
                            .\(functionName)(\(paramName): \(paramName))
                        }
                        """)

                        generatedMembers.append("""
                        struct \(functionName)Stub {
                            let \(paramName): Parameter<\(paramType)>
                            let returnValue: \(returnType)
                        }
                        """)

                        generatedMembers.append("var \(functionName)Stubs: [\(functionName)Stub] = []")

                        generatedMembers.append("""
                        func \(baseName)\(signature.description) {
                            \(functionName)CallCount += 1
                            invocations.append(.\(functionName)_invocation(\(paramName): \(paramName)))

                            for stub in \(functionName)Stubs {
                                if stub.\(paramName).matches(\(paramName)) {
                                    return stub.returnValue
                                }
                            }
                            fatalError("No stub for \(functionName)")
                        }
                        """)

                        givenCases.append("""
                        case .\(functionName)(let \(paramName), let returnValue):
                            \(functionName)Stubs.append(\(functionName)Stub(\(paramName): \(paramName), returnValue: returnValue))
                        """)

                        verifyCases.append("""
                        case .\(functionName)(let expectedParam):
                            actual = invocations.filter {
                                if case .\(functionName)_invocation(let actualParam) = $0 {
                                    return expectedParam.matches(actualParam)
                                }
                                return false
                            }.count
                        """)
                    }

                } else {

                    methodEnumCases.append("case \(functionName)")
                    methodEnumCases.append("case \(functionName)_invocation")

                    verifyMethodCases.append("case \(functionName)")

                    verifyHelperFunctions.append("""
                    static func \(baseName)() -> VerifyMethod {
                        .\(functionName)
                    }
                    """)

                    generatedMembers.append("""
                    func \(baseName)\(signature.description) {
                        \(functionName)CallCount += 1
                        invocations.append(.\(functionName)_invocation)
                    }
                    """)

                    givenCases.append("case .\(functionName): break")

                    verifyCases.append("""
                    case .\(functionName):
                        actual = invocations.filter {
                            if case .\(functionName)_invocation = $0 { return true }
                            return false
                        }.count
                    """)
                }
            }

            // -------- PROPERTIES --------
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let type = binding.typeAnnotation?.type.description {

                let propertyName = identifier.identifier.text
                let propertyType = type.trimmingCharacters(in: .whitespacesAndNewlines)

                let capitalized = propertyName.prefix(1).uppercased() + propertyName.dropFirst()

                let getCase = "get\(capitalized)"
                let setCase = "set\(capitalized)"

                methodEnumCases.append("case \(getCase)(returnValue: \(propertyType))")
                methodEnumCases.append("case \(setCase)")
                methodEnumCases.append("case \(getCase)_invocation")
                methodEnumCases.append("case \(setCase)_invocation")

                verifyMethodCases.append("case \(getCase)")
                verifyMethodCases.append("case \(setCase)")

                // 🆕 FIX: helper for verify
                verifyHelperFunctions.append("""
                static func \(getCase)() -> VerifyMethod { .\(getCase) }
                """)

                helperFunctions.append("""
                static func \(getCase)(willReturn: \(propertyType)) -> Method {
                    .\(getCase)(returnValue: willReturn)
                }
                """)

                generatedMembers.append("var \(propertyName)GetCallCount = 0")
                generatedMembers.append("var \(propertyName)SetCallCount = 0")
                generatedMembers.append("var _\(propertyName): \(propertyType)?")

                generatedMembers.append("""
                var \(propertyName): \(propertyType) {
                    get {
                        \(propertyName)GetCallCount += 1
                        invocations.append(.\(getCase)_invocation)

                        if let value = _\(propertyName) {
                            return value
                        }
                        fatalError("No stub for property \(propertyName)")
                    }
                    set {
                        \(propertyName)SetCallCount += 1
                        invocations.append(.\(setCase)_invocation)
                        _\(propertyName) = newValue
                    }
                }
                """)

                givenCases.append("""
                case .\(getCase)(let returnValue):
                    self._\(propertyName) = returnValue
                """)

                verifyCases.append("""
                case .\(getCase):
                    actual = invocations.filter {
                        if case .\(getCase)_invocation = $0 { return true }
                        return false
                    }.count
                """)

                verifyCases.append("""
                case .\(setCase):
                    actual = invocations.filter {
                        if case .\(setCase)_invocation = $0 { return true }
                        return false
                    }.count
                """)
            }
        } // 🛠 FIXED: missing brace

        let methodEnumBlock = """
        enum Method {
        \(methodEnumCases.joined(separator: "\n"))
        \(helperFunctions.joined(separator: "\n"))
        }
        """

        let verifyEnumBlock = """
        enum VerifyMethod {
        \(verifyMethodCases.joined(separator: "\n"))
        \(verifyHelperFunctions.joined(separator: "\n"))
        }
        """

        let givenFunction = """
        func given(_ method: Method) {
            switch method {
            \(givenCases.joined(separator: "\n"))
            default: break
            }
        }
        """

        let verifyFunction = """
        func verify(_ method: VerifyMethod, count expected: Int) {
            let actual: Int

            switch method {
            \(verifyCases.joined(separator: "\n"))
            default: actual = 0
            }

            if actual != expected {
                fatalError("Verify failed: expected \\(expected) calls, got \\(actual)")
            }
        }
        """

        let mockClass = """
        final class \(mockName): \(protocolName) {

        \(methodEnumBlock)

        \(verifyEnumBlock)

        var invocations: [Method] = []

        \(generatedMembers.joined(separator: "\n\n"))

        \(givenFunction)

        \(verifyFunction)
        }
        """

        return [DeclSyntax(stringLiteral: mockClass)]
    }
}
