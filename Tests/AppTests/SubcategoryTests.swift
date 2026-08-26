import Testing
import VaporTesting

@testable import App

/// Same seam as `SprintTests`/`CategoryTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Subcategories", .serialized)
    struct SubcategoryTests {
        @discardableResult
        private func withSubcategoriesApp<T>(_ test: (Application) async throws -> T) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                try await configure(app)
            }) { app in
                let result = try await test(app)
                try await Transaction.query(on: app.db).delete()
                try await Account.query(on: app.db).delete()
                try await Subcategory.query(on: app.db).delete()
                try await PCCCategory.query(on: app.db).delete()
                return result
            }
        }

        private func authHeaders() -> HTTPHeaders {
            ["Authorization": "Bearer test-token-one"]
        }

        @Test("rejects requests without a bearer token")
        func subcategoriesWithoutTokenAreRejected() async throws {
            try await withSubcategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/subcategories?categoryID=\(try category.requireID())",
                    afterResponse: { res async in
                        #expect(res.status == .unauthorized)
                    }
                )
            }
        }

        @Test("creates a Subcategory with a name within a Category")
        func createsASubcategory() async throws {
            try await withSubcategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)
                let categoryID = try category.requireID()

                try await app.testing().test(
                    .POST, "/v1/subcategories",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveSubcategoryRequest(categoryID: categoryID, name: "Groceries"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(SubcategoryResponse.self)
                        #expect(body.name == "Groceries")
                        #expect(body.categoryID == categoryID)
                    }
                )

                let stored = try await Subcategory.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "Groceries")
            }
        }

        @Test("rejects creating a Subcategory with an empty or whitespace-only name")
        func rejectsEmptySubcategoryName() async throws {
            try await withSubcategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)

                try await app.testing().test(
                    .POST, "/v1/subcategories",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveSubcategoryRequest(categoryID: try category.requireID(), name: "   "))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await Subcategory.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects creating a Subcategory with a nonexistent categoryID")
        func rejectsMissingCategoryOnCreate() async throws {
            try await withSubcategoriesApp { app in
                try await app.testing().test(
                    .POST, "/v1/subcategories",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveSubcategoryRequest(categoryID: UUID(), name: "Groceries"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("edits a Subcategory's name")
        func editsASubcategoryName() async throws {
            try await withSubcategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)
                let subcategory = Subcategory(name: "Original", categoryID: try category.requireID())
                try await subcategory.save(on: app.db)
                let id = try subcategory.requireID()

                try await app.testing().test(
                    .PUT, "/v1/subcategories/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(UpdateSubcategoryRequest(name: "Renamed"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(SubcategoryResponse.self)
                        #expect(body.name == "Renamed")
                    }
                )

                let stored = try await Subcategory.find(id, on: app.db)
                #expect(stored?.name == "Renamed")
            }
        }

        @Test("editing a Subcategory that doesn't exist 404s")
        func editingMissingSubcategoryFails() async throws {
            try await withSubcategoriesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/subcategories/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(UpdateSubcategoryRequest(name: "Doesn't matter"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Subcategory")
        func deletesASubcategory() async throws {
            try await withSubcategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)
                let subcategory = Subcategory(name: "Throwaway", categoryID: try category.requireID())
                try await subcategory.save(on: app.db)
                let id = try subcategory.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/subcategories/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Subcategory.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Subcategory that doesn't exist 404s")
        func deletingMissingSubcategoryFails() async throws {
            try await withSubcategoriesApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/subcategories/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test(
            "deleting a Subcategory orphans a referencing Transaction's subcategoryID, leaving its categoryID intact"
        )
        func deletingSubcategoryOrphansReferencingTransactionOnly() async throws {
            try await withSubcategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)
                let categoryID = try category.requireID()
                let subcategory = Subcategory(name: "Groceries", categoryID: categoryID)
                try await subcategory.save(on: app.db)
                let subcategoryID = try subcategory.requireID()
                let account = Account(name: "Checking", type: .checking, openingBalance: 0)
                try await account.save(on: app.db)
                let transaction = Transaction(
                    amount: 10, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: try account.requireID(), categoryID: categoryID, subcategoryID: subcategoryID
                )
                try await transaction.save(on: app.db)
                let transactionID = try transaction.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/subcategories/\(subcategoryID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Transaction.find(transactionID, on: app.db)
                #expect(stored != nil)
                #expect(stored?.$subcategory.id == nil)
                #expect(stored?.$category.id == categoryID)
            }
        }

        @Test("lists Subcategories scoped to one Category")
        func listsSubcategoriesScopedToCategory() async throws {
            try await withSubcategoriesApp { app in
                let categoryA = PCCCategory(name: "Food")
                let categoryB = PCCCategory(name: "Transport")
                try await categoryA.save(on: app.db)
                try await categoryB.save(on: app.db)
                let categoryAID = try categoryA.requireID()
                try await Subcategory(name: "Groceries", categoryID: categoryAID).save(on: app.db)
                try await Subcategory(name: "Gas", categoryID: try categoryB.requireID()).save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/subcategories?categoryID=\(categoryAID)",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([SubcategoryResponse].self)
                        #expect(body.count == 1)
                        #expect(body.first?.name == "Groceries")
                    }
                )
            }
        }

        @Test("listing Subcategories without a categoryID 400s")
        func listingSubcategoriesWithoutCategoryIDFails() async throws {
            try await withSubcategoriesApp { app in
                try await app.testing().test(
                    .GET, "/v1/subcategories",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("listing Subcategories with a malformed categoryID 400s")
        func listingSubcategoriesWithMalformedCategoryIDFails() async throws {
            try await withSubcategoriesApp { app in
                try await app.testing().test(
                    .GET, "/v1/subcategories?categoryID=not-a-uuid",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }
    }
}
