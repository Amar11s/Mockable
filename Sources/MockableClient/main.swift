import Mockable


@Mockable
protocol UserService {
    var username: String { get set }
    func fetchUser(user name: String) -> String
    func fetchUser(name:Int) -> String

}

let mock = MockUserService()

mock.username = "test"
mock.given(.fetchUser_String(name: "", willReturn: "Hi"))
print(mock.fetchUser(user: ""))
