import Vapor

func routes(_ app: Application) throws {
    let v1 = app.grouped("v1")
    try v1.register(collection: HealthController())
    try v1.register(collection: ProjectController())
    try v1.register(collection: ClientController())
    try v1.register(collection: TaskController())
    try v1.register(collection: SprintController())
    try v1.register(collection: DeadlineController())
    try v1.register(collection: PersonalCommitmentController())
    try v1.register(collection: MirroredCalendarEventController())
    try v1.register(collection: AutomationLogController())
    try v1.register(collection: CourseController())
    try v1.register(collection: TimeEntryController())
    try v1.register(collection: WorkHoursController())
    try v1.register(collection: AccountController())
    try v1.register(collection: TransactionController())
    try v1.register(collection: CategoryController())
    try v1.register(collection: SubcategoryController())
    try v1.register(collection: FinancesReportingController())
    try v1.register(collection: NotificationController())
}
