import Mockable

@Mockable
protocol UserService {
    var username: String { get set }
    func fetchUser() -> String
    func fetchUser(completion: @escaping (String) -> Void)
}


let mock = MockUserService()

mock.given(.get_username, willReturn: "Alice")
mock.given(.fe, willReturn: <#T##T#>)

print(mock.username)

mock.username = "Bob"

mock.verify(.get_username, count: 1)
mock.verify(.set_username, count: 1)

print("property verify passed")

