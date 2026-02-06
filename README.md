# Mockable

Lightweight Swift macro-based mock generator.

## Usage

```swift
import Mockable

@Mockable
protocol UserService {
    func fetchUser() -> String
}

let mock = MockUserService()
mock.given(.fetchUser, willReturn: "Test")
mock.verify(.fetchUser, count: 1)

