import Vapor

func routes(_ app: Application) throws {
    let v1 = app.grouped("v1")
    try v1.register(collection: HealthController())
    try v1.register(collection: ProjectController())
    try v1.register(collection: TaskController())
    try v1.register(collection: DeadlineController())
    try v1.register(collection: PersonalCommitmentController())
}
