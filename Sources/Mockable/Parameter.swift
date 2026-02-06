//
//  Parameter.swift
//  Mockable
//
//  Created by amarendra singh on 07/02/26.
//

public enum Parameter<T: Equatable> {
    case value(T)
    case any

    public func matches(_ input: T) -> Bool {
        switch self {
        case .any: return true
        case .value(let v): return v == input
        }
    }
}
