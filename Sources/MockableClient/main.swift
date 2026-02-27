import Mockable


@Mockable
protocol UserService {
    var  name:String {get set}
    func fetchUser(name:String) -> String
    func fetchUser(noname:Int) -> Int

}

let mock = MockUserService()

mock.given(.fetchUser(noname: .any, willReturn:1 ))
mock.given(.getName(willReturn: "Amar"))

print(mock.name)

mock.verify(.fetchUser(noname:.any), count: 0)

