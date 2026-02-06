import Mockable

@Mockable
protocol UserService {
    var username: String { get set }
    func fetchUser() -> String
    func fetchUser(completion: @escaping (String) -> Void)
}

print("=== Testing MockUserService ===\n")

// Test 1: Basic property get/set
print("Test 1: Basic property get/set")
let mock = MockUserService()
mock.given(.get_username(willReturn: "TestUser"))
assert(mock.username == "TestUser")
mock.username = "NewUser"
mock.verify(.set_username(value: .any), count: 1)
print("✅ Property get/set works\n")

// Test 2: Parameterless function with return value
print("Test 2: Parameterless function with return value")
mock.given(.fetchUser(willReturn: "John"))
let result = mock.fetchUser()
assert(result == "John")
mock.verify(.fetchUser(willReturn: ""), count: 1)
print("✅ Parameterless fetchUser works\n")

// Test 3: Override return value
print("Test 3: Override return value")
let freshMock = MockUserService()
freshMock.given(.fetchUser(willReturn: "First"))
assert(freshMock.fetchUser() == "First")
freshMock.given(.fetchUser(willReturn: "Second"))
assert(freshMock.fetchUser() == "Second")
freshMock.verify(.fetchUser(willReturn: ""), count: 2)
print("✅ Return value override works\n")

// Test 4: Void function with completion handler
print("Test 4: Void function with completion handler")
let completionMock = MockUserService()

var capturedResult = ""
var completionCallCount = 0

completionMock.fetchUser { result in
    capturedResult = result
    completionCallCount += 1
}

// Verify the call was recorded
completionMock.verify(.fetchUser_with_completion(completion: .any), count: 1)

// Trigger the stored completion
completionMock.triggerFetchUserCompletions(with: "AsyncResult")

// Check that completion was called
assert(completionCallCount == 1, "Completion should have been called once")
assert(capturedResult == "AsyncResult", "Expected 'AsyncResult', got '\(capturedResult)'")
print("✅ Completion handler works with trigger method\n")

// Test 5: Multiple completions (simplified)
print("Test 5: Multiple completions")
let multiMock = MockUserService()

var results: [String] = []
multiMock.fetchUser { result in
    results.append("1: \(result)")
}
multiMock.fetchUser { result in
    results.append("2: \(result)")
}

assert(multiMock.fetchUser_with_completionCallCount == 2)

// Trigger all completions
multiMock.triggerFetchUserCompletions(with: "BatchResult")

assert(results.count == 2)
assert(results.contains("1: BatchResult"))
assert(results.contains("2: BatchResult"))
print("✅ Multiple completions work\n")

// Test 6: Property operations with exact matching
print("Test 6: Property operations with exact matching")
let exactMock = MockUserService()
exactMock.username = "SpecificValue"
exactMock.verify(.set_username(value: .value("SpecificValue")), count: 1)
exactMock.verify(.set_username(value: .value("WrongValue")), count: 0)
print("✅ Exact value matching works\n")

// Test 7: Verify no calls
print("Test 7: Verify no calls")
let untouchedMock = MockUserService()
untouchedMock.verify(.fetchUser(willReturn: ""), count: 0)
untouchedMock.verify(.set_username(value: .any), count: 0)
print("✅ Zero count verification works\n")

// Test 8: Using .any for verification
print("Test 8: Using .any for verification")
let anyMock = MockUserService()
anyMock.username = "Value1"
anyMock.username = "Value2"
anyMock.verify(.set_username(value: .any), count: 2)
print("✅ Any value matching works\n")

// Test 9: Trigger completions multiple times
print("Test 9: Trigger completions multiple times")
let triggerMock = MockUserService()

var triggerCount = 0
triggerMock.fetchUser { _ in
    triggerCount += 1
}

triggerMock.triggerFetchUserCompletions(with: "First")
assert(triggerCount == 1)

// Calling trigger again shouldn't do anything since completions were cleared
triggerMock.triggerFetchUserCompletions(with: "Second")
assert(triggerCount == 1) // Still 1 because completions were cleared
print("✅ Trigger clears completions after calling them\n")

print("=== All tests completed successfully! ===")
