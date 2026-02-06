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
        var methodEnumCases: [String] = []
        var givenCases: [String] = []
        var verifyCases: [String] = []
        var argumentMatcherStructs: [String] = []

        // Add ArgumentMatcher enum at the top
        argumentMatcherStructs.append("""
        enum Arg {
            case any
            case value(Any)
            
            func matches(_ value: Any) -> Bool {
                switch self {
                case .any:
                    return true
                case .value(let expected):
                    return String(describing: expected) == String(describing: value)
                }
            }
        }
        """)

        for member in protocolDecl.memberBlock.members {
            // -------- FUNCTIONS --------
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let baseName = funcDecl.name.text
                let signature = funcDecl.signature
                let returnType = signature.returnClause?.type.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Build parameter info
                let parameters = funcDecl.signature.parameterClause.parameters
                let paramNames: [String] = parameters.map { $0.firstName.text }
                let paramTypes: [String] = parameters.map {
                    $0.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Create a unique identifier for overloaded functions
                let isVoidReturn = returnType == nil || returnType == "Void"
                let hasParameters = !parameters.isEmpty
                
                // Generate a suffix based on parameters to avoid conflicts
                let overloadSuffix: String
                if paramNames.isEmpty {
                    overloadSuffix = isVoidReturn ? "_void" : ""
                } else {
                    overloadSuffix = "_with_" + paramNames.joined(separator: "_")
                }
                
                let uniqueName = baseName + overloadSuffix

                // Create method case with embedded willReturn
                if paramNames.isEmpty {
                    // Parameterless function
                    if !isVoidReturn, let returnType = returnType {
                        methodEnumCases.append("case \(uniqueName)(willReturn: \(returnType))")
                    } else {
                        methodEnumCases.append("case \(uniqueName)")
                    }
                } else {
                    // Function with parameters
                    let paramLabels = paramNames.map { "\($0): Arg" }.joined(separator: ", ")
                    if !isVoidReturn, let returnType = returnType {
                        methodEnumCases.append("case \(uniqueName)(\(paramLabels), willReturn: \(returnType))")
                    } else {
                        methodEnumCases.append("case \(uniqueName)(\(paramLabels))")
                    }
                }

                // Generate call tracking struct for this method
                if !paramNames.isEmpty {
                    var paramStructFields: [String] = []
                    var paramInitializers: [String] = []
                    
                    for (index, paramName) in paramNames.enumerated() {
                        paramStructFields.append("let \(paramName): \(paramTypes[index])")
                        paramInitializers.append("self.\(paramName) = \(paramName)")
                    }
                    
                    let paramStructName = "\(baseName.capitalized)Params\(overloadSuffix)"
                    argumentMatcherStructs.append("""
                    struct \(paramStructName) {
                        \(paramStructFields.joined(separator: "\n        "))
                        
                        init(\(paramNames.map { "\($0): \(paramTypes[$0 == paramNames.first! ? 0 : 1])" }.joined(separator: ", "))) {
                            \(paramInitializers.joined(separator: "\n            "))
                        }
                    }
                    """)
                }

                // Store calls and return values
                if paramNames.isEmpty {
                    // Parameterless function
                    if !isVoidReturn, let returnType = returnType {
                        generatedMembers.append("var \(uniqueName)ReturnValue: \(returnType)?")
                        generatedMembers.append("var \(uniqueName)CallCount = 0")
                        
                        generatedMembers.append("""
                        func \(baseName)() -> \(returnType) {
                            \(uniqueName)CallCount += 1
                            if let value = \(uniqueName)ReturnValue {
                                return value
                            }
                            fatalError("No stub for \(baseName)")
                        }
                        """)
                        
                        givenCases.append("""
                        case .\(uniqueName)(let willReturn):
                            self.\(uniqueName)ReturnValue = willReturn
                        """)
                        
                        verifyCases.append("""
                        case .\(uniqueName):
                            actual = self.\(uniqueName)CallCount
                        """)
                    } else {
                        // Void parameterless function
                        generatedMembers.append("var \(uniqueName)CallCount = 0")
                        
                        generatedMembers.append("""
                        func \(baseName)() {
                            \(uniqueName)CallCount += 1
                        }
                        """)
                        
                        givenCases.append("""
                        case .\(uniqueName):
                            break
                        """)
                        
                        verifyCases.append("""
                        case .\(uniqueName):
                            actual = self.\(uniqueName)CallCount
                        """)
                    }
                } else {
                    // Function with parameters
                    if !isVoidReturn, let returnType = returnType {
                        let paramStructName = "\(baseName.capitalized)Params\(overloadSuffix)"
                        generatedMembers.append("var \(uniqueName)Calls: [\(paramStructName): \(returnType)?] = [:]")
                        
                        // Function implementation
                        let paramsInit = "\(paramStructName)(\(paramNames.map { "\($0): \($0)" }.joined(separator: ", ")))"
                        
                        generatedMembers.append("""
                        func \(baseName)(\(parameters.map { "\($0.firstName.text): \($0.type)" }.joined(separator: ", "))) -> \(returnType) {
                            let params = \(paramsInit)
                            if let returnValue = self.\(uniqueName)Calls[params] {
                                return returnValue
                            }
                            fatalError("No stub for \(baseName) with given parameters")
                        }
                        """)
                        
                        // Given implementation
                        givenCases.append("""
                        case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", ")), let willReturn):
                            let params = \(paramsInit)
                            self.\(uniqueName)Calls[params] = willReturn
                        """)
                        
                        // Verify implementation
                        verifyCases.append("""
                        case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", ")), _):
                            let params = \(paramsInit)
                            actual = self.\(uniqueName)Calls.keys.filter { key in
                                \(paramNames.map { paramName in
                                    "\(paramName).matches(key.\(paramName))"
                                }.joined(separator: " && "))
                            }.count
                        """)
                    } else {
                        // Void function with parameters
                        let paramStructName = "\(baseName.capitalized)Params\(overloadSuffix)"
                        generatedMembers.append("var \(uniqueName)Calls: [\(paramStructName)] = []")
                        
                        let paramsInit = "\(paramStructName)(\(paramNames.map { "\($0): \($0)" }.joined(separator: ", ")))"
                        
                        generatedMembers.append("""
                        func \(baseName)(\(parameters.map { "\($0.firstName.text): \($0.type)" }.joined(separator: ", "))) {
                            let params = \(paramsInit)
                            self.\(uniqueName)Calls.append(params)
                        }
                        """)
                        
                        givenCases.append("""
                        case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", "))):
                            // Record the pattern for void functions
                            let params = \(paramsInit)
                            self.\(uniqueName)Calls.append(params)
                        """)
                        
                        verifyCases.append("""
                        case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", "))):
                            actual = self.\(uniqueName)Calls.filter { call in
                                \(paramNames.map { paramName in
                                    "\(paramName).matches(call.\(paramName))"
                                }.joined(separator: " && "))
                            }.count
                        """)
                    }
                }
            }

            // -------- PROPERTIES --------
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let type = binding.typeAnnotation?.type.description
            {
                let propertyName = identifier.identifier.text
                let propertyType = type.trimmingCharacters(in: .whitespacesAndNewlines)

                methodEnumCases.append("case get_\(propertyName)(willReturn: \(propertyType))")
                methodEnumCases.append("case set_\(propertyName)(value: Arg)")

                generatedMembers.append("var \(propertyName)GetCallCount = 0")
                generatedMembers.append("var \(propertyName)SetCalls: [Any] = []")
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
                        \(propertyName)SetCalls.append(newValue)
                        _\(propertyName) = newValue
                    }
                }
                """)

                // Given implementation for properties
                givenCases.append("""
                case .get_\(propertyName)(let willReturn):
                    self._\(propertyName) = willReturn
                case .set_\(propertyName)(let value):
                    self.\(propertyName)SetCalls.append(value)
                """)

                // Verify implementation for properties
                verifyCases.append("""
                case .get_\(propertyName):
                    actual = self.\(propertyName)GetCallCount
                case .set_\(propertyName)(let value):
                    actual = self.\(propertyName)SetCalls.filter { value.matches($0) }.count
                """)
            }
        }

        let enumBlock = """
        \(argumentMatcherStructs.joined(separator: "\n\n"))
        
        enum Method {
        \(methodEnumCases.joined(separator: "\n"))
        }
        """

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
        func verify(_ method: Method, count expected: Int, file: StaticString = #file, line: UInt = #line) {
            var actual = 0
            switch method {
            \(verifyCases.joined(separator: "\n"))
            default:
                break
            }
            if actual != expected {
                fatalError("\\(file):\\(line) - Verify failed: expected \\(expected) calls, got \\(actual)")
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
