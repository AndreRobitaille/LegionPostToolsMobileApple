import Foundation

/// An in-memory view of a freshly fetched export. Unknown or disallowed fields
/// cannot accidentally leak into Contacts merely because they were in JSON.
public struct PermittedContactCopy: Equatable, Sendable {
    public let firstName: String
    public let lastName: String
    public let company: String
    public let phone: String?
    public let email: String?
    public let address: ContactExportResponse.Address?
    public let version: String
    public init(_ projection: ContactExportResponse) throws {
        let permitted = Set(projection.permittedFields)
        guard permitted.isSuperset(of: ["first_name", "last_name", "company"]) else { throw ClientError.invalidResponse }
        firstName = projection.fields.firstName; lastName = projection.fields.lastName; company = projection.fields.company
        phone = permitted.contains("phone") ? projection.fields.phone : nil
        email = permitted.contains("email") ? projection.fields.email : nil
        address = permitted.contains("address") && projection.addressCoverage == "reviewed_components" && (projection.addressReviewId ?? 0) > 0
            ? projection.fields.address : nil
        version = projection.version
    }
}
