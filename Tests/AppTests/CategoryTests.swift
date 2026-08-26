import Testing
import VaporTesting

@testable import App

/// Same seam as `ClientTests`/`AccountTests`: real HTTP requests against a
/// running Vapor app, backed by a real (test) Postgres database.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on each other's rows.
extension AppTestSuite {
    @Suite("Categories", .serialized)
    struct CategoryTests {
        @discardableResult
        private func withCategoriesApp<T>(_ test: (Application) async throws -> T) async throws -> T {
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
        func categoriesWithoutTokenAreRejected() async throws {
            try await withCategoriesApp { app in
                try await app.testing().test(.GET, "/v1/categories", afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
        }

        @Test("creates a Category with a name")
        func createsACategory() async throws {
            try await withCategoriesApp { app in
                try await app.testing().test(
                    .POST, "/v1/categories",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCategoryRequest(name: "Food"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CategoryResponse.self)
                        #expect(body.name == "Food")
                    }
                )

                let stored = try await PCCCategory.query(on: app.db).all()
                #expect(stored.count == 1)
                #expect(stored.first?.name == "Food")
            }
        }

        @Test("rejects creating a Category with an empty or whitespace-only name")
        func rejectsEmptyCategoryName() async throws {
            try await withCategoriesApp { app in
                try await app.testing().test(
                    .POST, "/v1/categories",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCategoryRequest(name: "   "))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )

                let stored = try await PCCCategory.query(on: app.db).all()
                #expect(stored.isEmpty)
            }
        }

        @Test("rejects a malformed Category id")
        func rejectsMalformedCategoryID() async throws {
            try await withCategoriesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/categories/not-a-uuid",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCategoryRequest(name: "Doesn't matter"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .badRequest)
                    }
                )
            }
        }

        @Test("lists all Categories")
        func listsAllCategories() async throws {
            try await withCategoriesApp { app in
                try await PCCCategory(name: "Food").save(on: app.db)
                try await PCCCategory(name: "Transport").save(on: app.db)

                try await app.testing().test(
                    .GET, "/v1/categories",
                    headers: authHeaders(),
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode([CategoryResponse].self)
                        #expect(body.count == 2)
                        #expect(Set(body.map(\.name)) == ["Food", "Transport"])
                    }
                )
            }
        }

        @Test("edits a Category's name")
        func editsACategoryName() async throws {
            try await withCategoriesApp { app in
                let category = PCCCategory(name: "Original")
                try await category.save(on: app.db)
                let id = try category.requireID()

                try await app.testing().test(
                    .PUT, "/v1/categories/\(id)",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCategoryRequest(name: "Renamed"))
                    },
                    afterResponse: { res async throws in
                        #expect(res.status == .ok)
                        let body = try res.content.decode(CategoryResponse.self)
                        #expect(body.name == "Renamed")
                    }
                )

                let stored = try await PCCCategory.find(id, on: app.db)
                #expect(stored?.name == "Renamed")
            }
        }

        @Test("editing a Category that doesn't exist 404s")
        func editingMissingCategoryFails() async throws {
            try await withCategoriesApp { app in
                try await app.testing().test(
                    .PUT, "/v1/categories/\(UUID())",
                    headers: authHeaders(),
                    beforeRequest: { req async throws in
                        try req.content.encode(SaveCategoryRequest(name: "Doesn't matter"))
                    },
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deletes a Category")
        func deletesACategory() async throws {
            try await withCategoriesApp { app in
                let category = PCCCategory(name: "Throwaway")
                try await category.save(on: app.db)
                let id = try category.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/categories/\(id)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await PCCCategory.find(id, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Category that doesn't exist 404s")
        func deletingMissingCategoryFails() async throws {
            try await withCategoriesApp { app in
                try await app.testing().test(
                    .DELETE, "/v1/categories/\(UUID())",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .notFound)
                    }
                )
            }
        }

        @Test("deleting a Category cascade-deletes its Subcategories")
        func deletingCategoryCascadesToSubcategories() async throws {
            try await withCategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)
                let categoryID = try category.requireID()
                let subcategory = Subcategory(name: "Groceries", categoryID: categoryID)
                try await subcategory.save(on: app.db)
                let subcategoryID = try subcategory.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/categories/\(categoryID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Subcategory.find(subcategoryID, on: app.db)
                #expect(stored == nil)
            }
        }

        @Test("deleting a Category orphans (rather than blocks) a Transaction that references it directly")
        func deletingCategoryOrphansReferencingTransaction() async throws {
            try await withCategoriesApp { app in
                let category = PCCCategory(name: "Food")
                try await category.save(on: app.db)
                let categoryID = try category.requireID()
                let account = Account(name: "Checking", type: .checking, openingBalance: 0)
                try await account.save(on: app.db)
                let transaction = Transaction(
                    amount: 10, type: .expense, date: Date(timeIntervalSince1970: 1_800_000_000),
                    accountID: try account.requireID(), categoryID: categoryID
                )
                try await transaction.save(on: app.db)
                let transactionID = try transaction.requireID()

                try await app.testing().test(
                    .DELETE, "/v1/categories/\(categoryID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Transaction.find(transactionID, on: app.db)
                #expect(stored != nil)
                #expect(stored?.$category.id == nil)
            }
        }

        @Test("deleting a Category orphans a Transaction tagged with one of its Subcategories")
        func deletingCategoryOrphansTransactionViaSubcategory() async throws {
            try await withCategoriesApp { app in
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
                    .DELETE, "/v1/categories/\(categoryID)",
                    headers: authHeaders(),
                    afterResponse: { res async in
                        #expect(res.status == .noContent)
                    }
                )

                let stored = try await Transaction.find(transactionID, on: app.db)
                #expect(stored != nil)
                #expect(stored?.$category.id == nil)
                #expect(stored?.$subcategory.id == nil)
            }
        }
    }
}
