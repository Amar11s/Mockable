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

        for member in protocolDecl.memberBlock.members {

            // -------- FUNCTIONS --------
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let baseName = funcDecl.name.text

                let paramNames: [String] = funcDecl.signature.parameterClause.parameters.compactMap {
                    $0.firstName.text
                }

                let overloadSuffix = paramNames.isEmpty
                    ? ""
                    : "_" + paramNames.joined(separator: "_")

                let functionName = baseName + overloadSuffix
                let signature = funcDecl.signature

                let returnType = signature.returnClause?.type.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                methodEnumCases.append("case \(functionName)")
                generatedMembers.append("var \(functionName)CallCount = 0")

                if let returnType = returnType {
                    generatedMembers.append("var \(functionName)ReturnValue: \(returnType)?")

                    generatedMembers.append("""
                    func \(baseName)\(signature.description) {
                        \(functionName)CallCount += 1
                        if let value = \(functionName)ReturnValue {
                            return value
                        }
                        fatalError("No stub for \(functionName)")
                    }
                    """)

                    givenCases.append("""
                    case .\(functionName):
                        self.\(functionName)ReturnValue = value as? \(returnType)
                    """)
                } else {
                    generatedMembers.append("""
                    func \(baseName)\(signature.description) {
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
               let type = binding.typeAnnotation?.type.description
            {
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

                givenCases.append("""
                case .get_\(propertyName):
                    self._\(propertyName) = value as? \(propertyType)
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

        let enumBlock = """
        enum Method {
        \(methodEnumCases.joined(separator: "\n"))
        }
        """

        let givenFunction = """
        func given<T>(_ method: Method, willReturn value: T) {
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
                fatalError("Verify failed: expected \\(expected) calls, got \\(actual)")
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
