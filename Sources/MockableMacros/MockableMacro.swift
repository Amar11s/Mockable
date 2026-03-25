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

        // MARK: - Helpers

        func normalizeType(_ type: String) -> String {
            return type
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "?", with: "Optional")
                .replacingOccurrences(of: "!", with: "IUO")
                .replacingOccurrences(of: "[", with: "ArrayOf")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "->", with: "To")
                .replacingOccurrences(of: ",", with: "_")
                .replacingOccurrences(of: ":", with: "_")
        }

        func paramDisplayName(_ param: FunctionParameterSyntax) -> String {
            if let second = param.secondName {
                return second.text
            }
            return param.firstName.text == "_" ? "param" : param.firstName.text
        }

        func paramType(_ param: FunctionParameterSyntax) -> String {
            return param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func buildSignatureSuffix(_ params: [FunctionParameterSyntax]) -> String {
            if params.isEmpty { return "" }

            let parts = params.map {
                normalizeType(paramType($0))
            }

            return "_" + parts.joined(separator: "_")
        }

        func buildParamList(_ params: [FunctionParameterSyntax]) -> String {
            return params.map {
                let name = paramDisplayName($0)
                let type = paramType($0)
                return "\(name): \(type)"
            }.joined(separator: ", ")
        }

        func buildStubStructParams(_ params: [FunctionParameterSyntax]) -> String {
            return params.map {
                let name = paramDisplayName($0)
                let type = paramType($0)
                return "let \(name): \(type)"
            }.joined(separator: "\n")
        }

        func buildStubMatchCondition(_ params: [FunctionParameterSyntax]) -> String {
            if params.isEmpty { return "true" }

            return params.map {
                let name = paramDisplayName($0)
                return "stub.\(name) == \(name)"
            }.joined(separator: " && ")
        }

        func buildCallArgs(_ params: [FunctionParameterSyntax]) -> String {
            return params.map {
                let name = paramDisplayName($0)
                return "\(name): \(name)"
            }.joined(separator: ", ")
        }

        func buildParamDecl(_ params: [FunctionParameterSyntax]) -> String {
            return params.map { param in
                let first = param.firstName.text
                let second = param.secondName?.text
                let type = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)

                if let second = second {
                    return "\(first) \(second): \(type)"
                } else {
                    return "\(first): \(type)"
                }
            }.joined(separator: ", ")
        }

        // MARK: - Iterate Members

        for member in protocolDecl.memberBlock.members {

            // -------- FUNCTIONS --------
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {

                let baseName = funcDecl.name.text
                let signature = funcDecl.signature
                let parameters = Array(signature.parameterClause.parameters)

                let suffix = buildSignatureSuffix(parameters)
                let functionName = baseName + suffix

                let returnType = signature.returnClause?.type.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                generatedMembers.append("var \(functionName)CallCount = 0")

                let paramList = buildParamList(parameters)
                let stubParams = buildStubStructParams(parameters)
                let matchCondition = buildStubMatchCondition(parameters)
                let callArgs = buildCallArgs(parameters)
                let paramDecl = buildParamDecl(parameters)

                // -------- WITH RETURN --------
                if let returnType = returnType, returnType != "Void" {

                    methodEnumCases.append("""
                    case \(functionName)(
                        \(paramList)\(paramList.isEmpty ? "" : ",")
                        willReturn: \(returnType)
                    )
                    """)

                    generatedMembers.append("""
                    struct \(functionName)Stub {
                    \(stubParams)
                    let returnValue: \(returnType)
                    }
                    """)

                    generatedMembers.append("""
                    var \(functionName)Stubs: [\(functionName)Stub] = []
                    """)

                    generatedMembers.append("""
                    func \(baseName)(\(paramDecl)) -> \(returnType) {
                        \(functionName)CallCount += 1
                        for stub in \(functionName)Stubs {
                            if \(matchCondition) {
                                return stub.returnValue
                            }
                        }
                        fatalError("No stub for \(functionName)")
                    }
                    """)

                    // 🔴 CHANGE 1: returnValue → willReturn (pattern + usage)
                    givenCases.append("""
                    case .\(functionName)(\(parameters.map { "let \(paramDisplayName($0))" }.joined(separator: ", ")), let willReturn):
                        \(functionName)Stubs.append(
                            \(functionName)Stub(
                                \(callArgs),
                                returnValue: willReturn
                            )
                        )
                    """)

                } else {
                    methodEnumCases.append("case \(functionName)")

                    generatedMembers.append("""
                    func \(baseName)(\(paramDecl)) {
                        \(functionName)CallCount += 1
                    }
                    """)

                    givenCases.append("""
                    case .\(functionName):
                        break
                    """)
                }

                verifyCases.append("""
                case .\(functionName):
                    actual = self.\(functionName)CallCount
                """)
            }

            // -------- PROPERTIES --------
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let type = binding.typeAnnotation?.type.description {

                let propertyName = identifier.identifier.text
                let propertyType = type.trimmingCharacters(in: .whitespacesAndNewlines)

                methodEnumCases.append("case get_\(propertyName)")
                methodEnumCases.append("case set_\(propertyName)")

                generatedMembers.append("var \(propertyName)GetCallCount = 0")
                generatedMembers.append("var \(propertyName)SetCallCount = 0")
                generatedMembers.append("var _\(propertyName): \(propertyType)?")

                generatedMembers.append("""
                var \(propertyName): \(propertyType) {
                    get {
                        \(propertyName)GetCallCount += 1
                        if let value = _\(propertyName) {
                            return value
                        }
                        fatalError("No stub for property \(propertyName)")
                    }
                    set {
                        \(propertyName)SetCallCount += 1
                        _\(propertyName) = newValue
                    }
                }
                """)

                // 🔴 CHANGE 2: remove usage of `value`
                givenCases.append("""
                case .get_\(propertyName):
                    fatalError("Use direct assignment for property \(propertyName)")
                """)

                verifyCases.append("""
                case .get_\(propertyName):
                    actual = self.\(propertyName)GetCallCount
                """)

                verifyCases.append("""
                case .set_\(propertyName):
                    actual = self.\(propertyName)SetCallCount
                """)
            }
        }

        // MARK: - Final Assembly

        let enumBlock = """
        enum Method {
        \(methodEnumCases.joined(separator: "\n"))
        }
        """

        // 🔴 CHANGE 3: removed generic + external willReturn
        let givenFunction = """
        func given(_ method: Method) {
            switch method {
            \(givenCases.joined(separator: "\n"))
            default:
                break
            }
        }
        """

        let verifyFunction = """
        func verify(_ method: Method, count expected: Int) {
            var actual = 0
            switch method {
            \(verifyCases.joined(separator: "\n"))
            default:
                break
            }
            if actual != expected {
                fatalError("Verify failed: expected \\(expected), got \\(actual)")
            }
        }
        """

        let mockClass = """
        final class \(mockName): \(protocolName) {

        \(enumBlock)

        \(generatedMembers.joined(separator: "\n\n"))

        \(givenFunction)

        \(verifyFunction)
        }
        """

        return [DeclSyntax(stringLiteral: mockClass)]
    }
}
