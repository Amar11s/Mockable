import Mockable

@Mockable
protocol UserService {
    var name: String { get set }

    func fetchUser(name: String) -> String
    func fetchUser(noname: Int) -> Int

    func getGreeting() -> String
}

let mock = MockUserService()

// GIVEN
mock.given(.fetchUser(noname: .any, willReturn: 1))
mock.given(.fetchUser(name: .value("amar"), willReturn: "User Amar"))
mock.given(.getName(willReturn: "Amar"))
mock.given(.getGreeting(willReturn: "Hello"))

// ACT
print(mock.name) // Amar

let result1 = mock.fetchUser(noname: 10)
let result2 = mock.fetchUser(name: "amar")
let greeting = mock.getGreeting()

print(result1)   // 1
print(result2)   // User Amar
print(greeting)  // Hello

// VERIFY
mock.verify(.getName(), count: 1)
mock.verify(.fetchUser(noname: .any), count: 1)
mock.verify(.fetchUser(name: .value("amar")), count: 1)
