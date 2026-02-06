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
        var helperMethods: [String] = []

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

        // Helper function to properly capitalize method names
        func capitalizeFirstLetter(_ string: String) -> String {
            guard let firstChar = string.first else { return string }
            return String(firstChar).uppercased() + string.dropFirst()
        }

        for member in protocolDecl.memberBlock.members {
            // -------- FUNCTIONS --------
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let baseName = funcDecl.name.text
                let capitalizedBaseName = capitalizeFirstLetter(baseName)
                let signature = funcDecl.signature
                let returnType = signature.returnClause?.type.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Build parameter info
                let parameters = funcDecl.signature.parameterClause.parameters
                let paramNames: [String] = parameters.map { $0.firstName.text }
                let paramTypes: [String] = parameters.map {
                    $0.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Check if any parameter is a closure
                let hasClosureParams = paramTypes.contains { type in
                    type.contains("->") || type.contains("@escaping")
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
                let methodCaseName = uniqueName

                // Create method case - only add it once
                if !methodEnumCases.contains(where: { $0.contains("case \(methodCaseName)") }) {
                    if paramNames.isEmpty {
                        // Parameterless function
                        if !isVoidReturn, let returnType = returnType {
                            methodEnumCases.append("case \(methodCaseName)(willReturn: \(returnType))")
                        } else {
                            methodEnumCases.append("case \(methodCaseName)")
                        }
                    } else {
                        // Function with parameters
                        let paramLabels = paramNames.map { "\($0): Arg" }.joined(separator: ", ")
                        if !isVoidReturn, let returnType = returnType {
                            methodEnumCases.append("case \(methodCaseName)(\(paramLabels), willReturn: \(returnType))")
                        } else {
                            methodEnumCases.append("case \(methodCaseName)(\(paramLabels))")
                        }
                    }
                }

                // Generate call tracking
                if !paramNames.isEmpty && hasClosureParams {
                    // For functions with closures
                    if !generatedMembers.contains(where: { $0.contains("var \(uniqueName)CallCount") }) {
                        generatedMembers.append("var \(uniqueName)CallCount = 0")
                        generatedMembers.append("var \(uniqueName)Completions: [(String) -> Void] = []")
                        
                        // Build function implementation - only add once
                        let paramsList = parameters.map { "\($0.firstName.text): \($0.type)" }.joined(separator: ", ")
                        
                        if isVoidReturn {
                            // Void function with closure parameter
                            generatedMembers.append("""
                            func \(baseName)(\(paramsList)) {
                                \(uniqueName)CallCount += 1
                                \(uniqueName)Completions.append(completion)
                            }
                            """)
                        }
                    }
                    
                    // Add trigger method for completions
                    if isVoidReturn && !helperMethods.contains(where: { $0.contains("func trigger\(capitalizedBaseName)Completions") }) {
                        helperMethods.append("""
                        func trigger\(capitalizedBaseName)Completions(with value: String) {
                            let completions = \(uniqueName)Completions
                            \(uniqueName)Completions.removeAll()
                            for completion in completions {
                                completion(value)
                            }
                        }
                        """)
                    }
                    
                    // Add given case - only once
                    if isVoidReturn && !givenCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                        givenCases.append("""
                        case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", "))):
                            // For void functions with closures, given just records the pattern
                            self.\(uniqueName)CallCount += 0 // No-op, just for pattern matching
                        """)
                    }
                    
                    // Add verify case - only once
                    if isVoidReturn && !verifyCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                        verifyCases.append("""
                        case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", "))):
                            actual = self.\(uniqueName)CallCount
                        """)
                    }
                } else if !paramNames.isEmpty && !hasClosureParams {
                    // For non-closure parameters
                    if !argumentMatcherStructs.contains(where: { $0.contains("struct \(capitalizedBaseName)Params\(overloadSuffix)") }) {
                        var paramStructFields: [String] = []
                        var paramInitializers: [String] = []
                        
                        for (index, paramName) in paramNames.enumerated() {
                            paramStructFields.append("let \(paramName): \(paramTypes[index])")
                            paramInitializers.append("self.\(paramName) = \(paramName)")
                        }
                        
                        let paramStructName = "\(capitalizedBaseName)Params\(overloadSuffix)"
                        argumentMatcherStructs.append("""
                        struct \(paramStructName): Hashable {
                            \(paramStructFields.joined(separator: "\n        "))
                            
                            init(\(paramNames.map { "\($0): \(paramTypes[$0 == paramNames.first! ? 0 : 1])" }.joined(separator: ", "))) {
                                \(paramInitializers.joined(separator: "\n            "))
                            }
                            
                            func hash(into hasher: inout Hasher) {
                                \(paramNames.map { "hasher.combine(\"\\(\($0))\")" }.joined(separator: "\n        "))
                            }
                            
                            static func == (lhs: \(paramStructName), rhs: \(paramStructName)) -> Bool {
                                \(paramNames.map { "\"\\(lhs.\($0))\" == \"\\(rhs.\($0))\"" }.joined(separator: "\n        && "))
                            }
                        }
                        """)
                    }
                }

                // Store calls and return values - only generate once per unique function
                if paramNames.isEmpty {
                    // Parameterless function
                    if !isVoidReturn, let returnType = returnType {
                        if !generatedMembers.contains(where: { $0.contains("var \(uniqueName)ReturnValue") }) {
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
                            
                            if !givenCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                                givenCases.append("""
                                case .\(uniqueName)(let willReturn):
                                    self.\(uniqueName)ReturnValue = willReturn
                                """)
                            }
                            
                            if !verifyCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                                verifyCases.append("""
                                case .\(uniqueName):
                                    actual = self.\(uniqueName)CallCount
                                """)
                            }
                        }
                    } else {
                        // Void parameterless function
                        if !generatedMembers.contains(where: { $0.contains("var \(uniqueName)CallCount") }) {
                            generatedMembers.append("var \(uniqueName)CallCount = 0")
                            
                            generatedMembers.append("""
                            func \(baseName)() {
                                \(uniqueName)CallCount += 1
                            }
                            """)
                            
                            if !givenCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                                givenCases.append("""
                                case .\(uniqueName):
                                    break
                                """)
                            }
                            
                            if !verifyCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                                verifyCases.append("""
                                case .\(uniqueName):
                                    actual = self.\(uniqueName)CallCount
                                """)
                            }
                        }
                    }
                } else if !paramNames.isEmpty && !hasClosureParams {
                    // Function with non-closure parameters
                    if !isVoidReturn, let returnType = returnType {
                        let paramStructName = "\(capitalizedBaseName)Params\(overloadSuffix)"
                        if !generatedMembers.contains(where: { $0.contains("var \(uniqueName)Calls") }) {
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
                            if !givenCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                                givenCases.append("""
                                case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", ")), let willReturn):
                                    let params = \(paramsInit)
                                    self.\(uniqueName)Calls[params] = willReturn
                                """)
                            }
                            
                            // Verify implementation
                            if !verifyCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                                verifyCases.append("""
                                case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", ")), _):
                                    let params = \(paramsInit)
                                    actual = self.\(uniqueName)Calls.keys.filter { key in
                                        \(paramNames.map { paramName in
                                            "\(paramName).matches(key.\(paramName))"
                                        }.joined(separator: " && "))
                                    }.count
                                """)
                            }
                        }
                    } else {
                        // Void function with non-closure parameters
                        let paramStructName = "\(capitalizedBaseName)Params\(overloadSuffix)"
                        if !generatedMembers.contains(where: { $0.contains("var \(uniqueName)Calls") }) {
                            generatedMembers.append("var \(uniqueName)Calls: [\(paramStructName)] = []")
                            
                            let paramsInit = "\(paramStructName)(\(paramNames.map { "\($0): \($0)" }.joined(separator: ", ")))"
                            
                            generatedMembers.append("""
                            func \(baseName)(\(parameters.map { "\($0.firstName.text): \($0.type)" }.joined(separator: ", "))) {
                                let params = \(paramsInit)
                                self.\(uniqueName)Calls.append(params)
                            }
                            """)
                            
                            if !givenCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
                                givenCases.append("""
                                case .\(uniqueName)(\(paramNames.map { "let \($0)" }.joined(separator: ", "))):
                                    let params = \(paramsInit)
                                    self.\(uniqueName)Calls.append(params)
                                """)
                            }
                            
                            if !verifyCases.contains(where: { $0.contains("case .\(uniqueName)") }) {
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
                }
            }

            // -------- PROPERTIES --------
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let type = binding.typeAnnotation?.type.description
            {
                let propertyName = identifier.identifier.text
                let capitalizedPropertyName = capitalizeFirstLetter(propertyName)
                let propertyType = type.trimmingCharacters(in: .whitespacesAndNewlines)

                // Add enum cases only once
                if !methodEnumCases.contains(where: { $0.contains("case get_\(propertyName)") }) {
                    methodEnumCases.append("case get_\(propertyName)(willReturn: \(propertyType))")
                }
                if !methodEnumCases.contains(where: { $0.contains("case set_\(propertyName)") }) {
                    methodEnumCases.append("case set_\(propertyName)(value: Arg)")
                }

                // Generate property implementation only once
                if !generatedMembers.contains(where: { $0.contains("var \(propertyName)GetCallCount") }) {
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
                }

                // Add given cases only once
                if !givenCases.contains(where: { $0.contains("case .get_\(propertyName)") }) {
                    givenCases.append("""
                    case .get_\(propertyName)(let willReturn):
                        self._\(propertyName) = willReturn
                    """)
                }
                if !givenCases.contains(where: { $0.contains("case .set_\(propertyName)") }) {
                    givenCases.append("""
                    case .set_\(propertyName)(let value):
                        self.\(propertyName)SetCalls.append(value)
                    """)
                }

                // Add verify cases only once
                if !verifyCases.contains(where: { $0.contains("case .get_\(propertyName)") }) {
                    verifyCases.append("""
                    case .get_\(propertyName):
                        actual = self.\(propertyName)GetCallCount
                    """)
                }
                if !verifyCases.contains(where: { $0.contains("case .set_\(propertyName)") }) {
                    verifyCases.append("""
                    case .set_\(propertyName)(let value):
                        actual = self.\(propertyName)SetCalls.filter { value.matches($0) }.count
                    """)
                }
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

        \(helperMethods.joined(separator: "\n\n"))

        \(givenFunction)

        \(verifyFunction)
        }
        """

        return [DeclSyntax(stringLiteral: mockClass)]
    }
}
