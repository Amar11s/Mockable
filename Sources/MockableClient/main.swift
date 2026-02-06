import Mockable


@Mockable
protocol UserService {
    var username: String { get set }
    func fetchUser(name:String) -> String
    func fetchUser(noname:Int) -> String

}

let mock = MockUserService()

mock.given(.get_username, willReturn: "john")

print( mock.username)

mock.verify(.get_username, count: 1)
