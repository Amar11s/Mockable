import Mockable

@Mockable
protocol UserService {
    var username: String { get set }
    func fetchUser() -> String
}


let mock = MockUserService()

mock.given(.get_username, willReturn: "Alice")

print(mock.username)

mock.username = "Bob"

mock.verify(.get_username, count: 1)
mock.verify(.set_username, count: 1)

print("property verify passed")

