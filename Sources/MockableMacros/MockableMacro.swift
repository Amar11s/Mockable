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
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else {
                continue
            }

            let functionName = funcDecl.name.text
            let signature = funcDecl.signature

            let returnType = signature.returnClause?.type.description
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // enum case
            methodEnumCases.append("case \(functionName)")

            // call tracking
            generatedMembers.append("var \(functionName)CallCount = 0")

            if let returnType = returnType {
                generatedMembers.append("var \(functionName)ReturnValue: \(returnType)?")

                generatedMembers.append("""
                func \(functionName)\(signature.description) {
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
                func \(functionName)\(signature.description) {
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

        let enumBlock = """
        enum Method {
        \(methodEnumCases.joined(separator: "\n"))
        }
        """

        let givenFunction = """
        func given<T>(_ method: Method, willReturn value: T) {
            switch method {
            \(givenCases.joined(separator: "\n"))
            }
        }
        """

        let verifyFunction = """
        func verify(_ method: Method, count expected: Int) {
            var actual = 0
            switch method {
            \(verifyCases.joined(separator: "\n"))
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
