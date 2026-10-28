import Foundation

/// Only an approval-required error may initiate an OS authorization request.
/// Cancellation never returns a credential to a later capture operation.
enum CredentialRead {
    static func value(noninteractive: () throws -> String, authorize: () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        do { let value = try noninteractive(); try Task.checkCancellation(); return value }
        catch KeychainAccessError.approvalRequired {
            try Task.checkCancellation()
            let result = try await authorize()
            try Task.checkCancellation()
            return result
        }
    }
}
