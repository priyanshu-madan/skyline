//
//  User.swift
//  SkyLine
//
//  User authentication models for Apple Sign In integration
//

import Foundation
import AuthenticationServices

// MARK: - User Model
struct User: Codable, Identifiable, Equatable {
    let id: String // Apple User ID
    let email: String?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let isEmailVerified: Bool
    let createdAt: Date
    let lastLoginAt: Date
    let profileImagePath: String?
    
    var displayName: String {
        if let fullName = fullName, !fullName.isEmpty {
            return fullName
        }
        
        if let firstName = firstName, !firstName.isEmpty {
            if let lastName = lastName, !lastName.isEmpty {
                return "\(firstName) \(lastName)"
            }
            return firstName
        }
        
        return email ?? "SkyLine User"
    }
    
    var initials: String {
        let name = displayName
        let components = name.components(separatedBy: " ")
        
        if components.count >= 2 {
            let firstInitial = String(components[0].prefix(1))
            let lastInitial = String(components[1].prefix(1))
            return "\(firstInitial)\(lastInitial)".uppercased()
        } else if let firstChar = name.first {
            return String(firstChar).uppercased()
        }
        
        return "SU" // SkyLine User
    }
}


// MARK: - Apple Sign In Extensions
extension ASAuthorizationAppleIDCredential {
    func toUser() -> User {
        return User(
            id: user,
            email: email,
            fullName: fullName?.formatted(),
            firstName: fullName?.givenName,
            lastName: fullName?.familyName,
            isEmailVerified: true, // Apple Sign In emails are always verified
            createdAt: Date(),
            lastLoginAt: Date(),
            profileImagePath: nil
        )
    }
}

extension PersonNameComponents {
    func formatted() -> String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter.string(from: self)
    }
}