import Mockable

@Mockable
protocol UserService {
    func fetchUser() -> String
}

let mock = MockUserService()

mock.given(.fetchUser, willReturn: "Test")

print(mock.fetchUser())
print(mock.fetchUser())

mock.verify(.fetchUser, count: 1)

print("verify passed")
