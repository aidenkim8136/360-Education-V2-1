import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import CoreData

// MARK: - Unread badge center
final class UnreadBadgeCenter: ObservableObject {
    static let shared = UnreadBadgeCenter()
    @Published var count: Int = 0
    private init() {}

    @MainActor
    func apply(total: Int) {
        count = max(total, 0)
        UIApplication.shared.applicationIconBadgeNumber = count
    }

}

// MARK: - Inbox badge watcher
final class InboxBadgeWatcher {
    static let shared = InboxBadgeWatcher()
    private var listener: ListenerRegistration?
    private var currentUid: String?
    private init() {}

    func start(myId: String) {
        guard currentUid != myId else { return }
        stop()
        currentUid = myId
        let db = Firestore.firestore()
        let ref = db.collection("dm_inbox").document(myId).collection("threads")
        listener = ref.addSnapshotListener(includeMetadataChanges: false) { snap, err in
            if let err = err { print("InboxBadgeWatcher error: \(err)"); return }
            guard let snap = snap else { return }
            var sum = 0
            for d in snap.documents {
                if let n = d["unreadCount"] as? Int { sum += n }
                else if let n = d["unreadCount"] as? NSNumber { sum += n.intValue }
            }
            Task { @MainActor in
                UnreadBadgeCenter.shared.apply(total: sum)
            }
        }
    }

    func stop() {
        listener?.remove(); listener = nil; currentUid = nil
    }
}

// MARK: - App Entry
@main
struct MatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = SessionViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}

// MARK: - AppDelegate (no push notifications)
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        UIApplication.shared.applicationIconBadgeNumber = 0
        Task { @MainActor in
            UnreadBadgeCenter.shared.apply(total: 0)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - Models
enum UserRole: String, Codable, CaseIterable, Identifiable {
    case student, teacher
    var id: String { rawValue }
    var label: String {
        switch self {
        case .student: return "Student"
        case .teacher: return "Teacher"
        }
    }
}

struct AppUser: Identifiable, Codable {
    let id: String
    let role: UserRole
    let name: String
    let email: String
    let gender: String
    let parentEmail: String?
    let parentPhone: String?
    let studentGrade: String?
    let teacherGradeOrOccupation: String?
    let teacherOtherExplanation: String?

    var asDict: [String: Any] {
        var d: [String: Any] = [
            "id": id,
            "role": role.rawValue,
            "name": name,
            "email": email,
            "gender": gender,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let parentEmail = parentEmail { d["parentEmail"] = parentEmail }
        if let parentPhone = parentPhone { d["parentPhone"] = parentPhone }
        if let studentGrade = studentGrade { d["studentGrade"] = studentGrade }
        if let teacherGradeOrOccupation = teacherGradeOrOccupation { d["teacherGradeOrOccupation"] = teacherGradeOrOccupation }
        if let teacherOtherExplanation = teacherOtherExplanation { d["teacherOtherExplanation"] = teacherOtherExplanation }
        return d
    }
}

private let DM_THREADS = "dm_threads"
private let USERS_COLLECTION = "users_v2"

// MARK: - Session ViewModel
@MainActor
final class SessionViewModel: ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var appUser: AppUser?
    @Published var isLoading = false
    private var handle: AuthStateDidChangeListenerHandle?
    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                if let uid = user?.uid {
                    await self?.fetchAppUser(uid: uid)
                } else {
                    self?.appUser = nil
                }
            }
        }
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        self.appUser = nil
    }

    func fetchAppUser(uid: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let doc = try await db.collection(USERS_COLLECTION).document(uid).getDocument()
            if let data = doc.data(),
               let roleRaw = data["role"] as? String,
               let role = UserRole(rawValue: roleRaw),
               let name = data["name"] as? String,
               let email = data["email"] as? String,
               let gender = data["gender"] as? String {
                self.appUser = AppUser(
                    id: uid,
                    role: role,
                    name: name,
                    email: email,
                    gender: gender,
                    parentEmail: data["parentEmail"] as? String,
                    parentPhone: data["parentPhone"] as? String,
                    studentGrade: data["studentGrade"] as? String,
                    teacherGradeOrOccupation: data["teacherGradeOrOccupation"] as? String,
                    teacherOtherExplanation: data["teacherOtherExplanation"] as? String
                )
            } else {
                self.appUser = nil
            }
        } catch {
            print("fetchAppUser error: \(error)")
        }
    }
}

let DM_INBOX = "dm_inbox"

// MARK: - Auth Mode
enum AuthMode { case login, signup }

// MARK: - Landing
struct LandingStartView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("Welcome To")
                            .font(.largeTitle).bold()
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        Text("360 Education with My Peers!")
                            .font(.title2).bold()
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    Spacer()
                    NavigationLink {
                        AuthModeChooserView()
                    } label: {
                        Text("Get Started")
                            .font(.headline).bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

struct AuthModeChooserView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Let's get you set up").font(.title2).bold().padding(.bottom, 8)
            Text("Choose an option below").foregroundStyle(.secondary)
            Spacer()
            NavigationLink { AuthView(startMode: .signup, showModePicker: false) } label: {
                Text("Sign Up").font(.headline).bold().frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            NavigationLink { AuthView(startMode: .login, showModePicker: false) } label: {
                Text("Log In").font(.headline).bold().frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Get Started")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Auth & Sign Up
struct AuthView: View {
    let showModePicker: Bool
    @State private var isSignUp: Bool

    init(startMode: AuthMode = .login, showModePicker: Bool = true) {
        self._isSignUp = State(initialValue: startMode == .signup)
        self.showModePicker = showModePicker
    }

    @State private var email = ""
    @State private var password = ""
    @State private var role: UserRole = .student
    @State private var name = ""
    @State private var gender = ""
    private let studentGrades = (1...8).map { "\($0)" }
    @State private var studentGrade = "1"
    @State private var parentEmail = ""
    @State private var parentPhone = ""
    private let teacherOptions = ["9","10","11","12","Current Teacher","Retired Teacher","Other"]
    @State private var teacherGradeOrOccupation = "9"
    @State private var teacherOtherExplanation = ""
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var showResetAlert = false
    @State private var resetNotice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showModePicker {
                        Picker("Mode", selection: $isSignUp) {
                            Text("Log In").tag(false)
                            Text("Sign Up").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password (min 6)", text: $password)
                        .textFieldStyle(.roundedBorder)
                    if !isSignUp {
                        Button("Forgot password?") { requestPasswordReset() }
                            .buttonStyle(.plain).padding(.top, 4)
                    }
                    if isSignUp {
                        Picker("I am a…", selection: $role) {
                            ForEach(UserRole.allCases) { r in Text(r.label).tag(r) }
                        }
                        .pickerStyle(.segmented)
                        TextField("Full Name", text: $name).textFieldStyle(.roundedBorder)
                        TextField("Gender", text: $gender).textFieldStyle(.roundedBorder)
                        if role == .student {
                            Menu {
                                ForEach(studentGrades, id: \.self) { grade in
                                    Button("\(grade)") { studentGrade = grade }
                                }
                            } label: {
                                HStack {
                                    Text("Grade Level").foregroundStyle(.primary)
                                    Spacer()
                                    Text("Grade \(studentGrade)")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.down").imageScale(.small).foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            TextField("Parent/Guardian Email", text: $parentEmail)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textFieldStyle(.roundedBorder)
                            TextField("Parent/Guardian Phone", text: $parentPhone)
                                .keyboardType(.phonePad)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Menu {
                                ForEach(teacherOptions, id: \.self) { option in
                                    Button(option) { teacherGradeOrOccupation = option }
                                }
                            } label: {
                                HStack {
                                    Text("Grade Level/Occupation").foregroundStyle(.primary)
                                    Spacer()
                                    Text(teacherGradeOrOccupation)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.down").imageScale(.small).foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            if teacherGradeOrOccupation == "Other" {
                                if #available(iOS 16.0, *) {
                                    TextField("Please explain (Other)", text: $teacherOtherExplanation, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    TextField("Please explain (Other)", text: $teacherOtherExplanation)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }
                    if let msg = errorMessage {
                        Text(msg).foregroundColor(.red)
                    }
                    Button {
                        Task { await handlePrimaryAction() }
                    } label: {
                        HStack {
                            if isBusy { ProgressView().padding(.trailing, 4) }
                            Text(isSignUp ? "Create Account" : "Log In").font(.headline).bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || email.isEmpty || password.isEmpty || (isSignUp && !signupFieldsValid))
                    Button(isSignUp ? "I already have an account" : "Create a new account") {
                        withAnimation { isSignUp.toggle() }
                    }
                    .buttonStyle(.plain).padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .alert("Password reset email sent", isPresented: $showResetAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetNotice ?? "We sent you a reset link. If you don't see it, check your spam or junk folder.")
            }
        }
    }

    private func requestPasswordReset() {
        errorMessage = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { errorMessage = "Enter your email above first."; return }
        Auth.auth().sendPasswordReset(withEmail: normalized) { err in
            if let err = err {
                errorMessage = err.localizedDescription
            } else {
                resetNotice = "We sent a reset link to \(normalized). If you don't see it, check your spam or junk folder."
                showResetAlert = true
            }
        }
    }

    private var signupFieldsValid: Bool {
        guard !name.isEmpty, !gender.isEmpty else { return false }
        if role == .student {
            return !parentEmail.isEmpty && !parentPhone.isEmpty && !studentGrade.isEmpty
        } else {
            return teacherGradeOrOccupation == "Other" ? !teacherOtherExplanation.isEmpty : true
        }
    }

    private func handlePrimaryAction() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            if isSignUp {
                let res = try await Auth.auth().createUser(withEmail: email, password: password)
                try await saveProfile(uid: res.user.uid)
            } else {
                _ = try await Auth.auth().signIn(withEmail: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile(uid: String) async throws {
        let db = Firestore.firestore()
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let appUser = AppUser(
            id: uid, role: role, name: name, email: normalizedEmail, gender: gender,
            parentEmail: role == .student ? parentEmail : nil,
            parentPhone: role == .student ? parentPhone : nil,
            studentGrade: role == .student ? studentGrade : nil,
            teacherGradeOrOccupation: role == .teacher ? teacherGradeOrOccupation : nil,
            teacherOtherExplanation: (role == .teacher && teacherGradeOrOccupation == "Other") ? teacherOtherExplanation : nil
        )
        try await db.collection(USERS_COLLECTION).document(uid).setData(appUser.asDict)
    }

}

// MARK: - Tab badge helper
extension View {
    @ViewBuilder
    func tabBadge(_ count: Int) -> some View {
        if count > 0 { self.badge(count) } else { self }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var selectedTab: Int = 0
    @ObservedObject private var badgeCenter = UnreadBadgeCenter.shared

    var isTeacher: Bool { session.appUser?.role == .teacher }

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if isTeacher { TeacherSubjectTabView(subject: "Music") }
                else { StudentSubjectTabView(subject: "Music") }
            }
            .tabItem { Label("Music", systemImage: "music.note") }
            .tag(0)

            Group {
                if isTeacher { TeacherSubjectTabView(subject: "Academic") }
                else { StudentSubjectTabView(subject: "Academic") }
            }
            .tabItem { Label("Academic", systemImage: "book") }
            .tag(1)

            ChatHomeView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tabBadge(badgeCenter.count)
                .tag(2)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(3)
        }
        .onChange(of: badgeCenter.count) { newValue in
            UIApplication.shared.applicationIconBadgeNumber = newValue
        }
    }
}

// MARK: - Models: Goal & Lesson

struct StudentGoal: Identifiable {
    let id: String           // docId = teacherId_studentId_subject
    let teacherId: String
    let studentId: String
    let studentName: String
    let teacherName: String
    let subject: String
    let goalText: String
    let notes: String
    let createdAt: Double
    let updatedAt: Double
}

struct LessonEntry: Identifiable {
    let id: String
    let teacherId: String
    let studentId: String
    let studentName: String
    let teacherName: String
    let subject: String
    let progressNote: String
    let notes: String
    let createdAt: Double
}

struct LessonComment: Identifiable {
    let id: String
    let lessonId: String
    let authorId: String
    let authorName: String
    let text: String
    let createdAt: Double
}

// MARK: - Firestore helpers

private func goalDocId(teacherId: String, studentId: String, subject: String) -> String {
    "\(teacherId)_\(studentId)_\(subject)"
}

private func decodeGoal(_ doc: DocumentSnapshot) -> StudentGoal? {
    guard let d = doc.data(),
          let teacherId = d["teacherId"] as? String,
          let studentId = d["studentId"] as? String,
          let subject = d["subject"] as? String,
          let goalText = d["goalText"] as? String else { return nil }
    return StudentGoal(
        id: doc.documentID, teacherId: teacherId, studentId: studentId,
        studentName: (d["studentName"] as? String) ?? "",
        teacherName: (d["teacherName"] as? String) ?? "",
        subject: subject, goalText: goalText,
        notes: (d["notes"] as? String) ?? "",
        createdAt: (d["createdAt"] as? Double) ?? 0,
        updatedAt: (d["updatedAt"] as? Double) ?? 0
    )
}

private func decodeLesson(_ doc: QueryDocumentSnapshot) -> LessonEntry? {
    let d = doc.data()
    guard let teacherId = d["teacherId"] as? String,
          let studentId = d["studentId"] as? String,
          let subject = d["subject"] as? String,
          let progressNote = d["progressNote"] as? String else { return nil }
    return LessonEntry(
        id: doc.documentID, teacherId: teacherId, studentId: studentId,
        studentName: (d["studentName"] as? String) ?? "",
        teacherName: (d["teacherName"] as? String) ?? "",
        subject: subject, progressNote: progressNote,
        notes: (d["notes"] as? String) ?? "",
        createdAt: (d["createdAt"] as? Double) ?? 0
    )
}

private func decodeComment(_ doc: QueryDocumentSnapshot) -> LessonComment? {
    let d = doc.data()
    guard let lessonId = d["lessonId"] as? String,
          let authorId = d["authorId"] as? String,
          let text = d["text"] as? String else { return nil }
    return LessonComment(
        id: doc.documentID, lessonId: lessonId, authorId: authorId,
        authorName: (d["authorName"] as? String) ?? "",
        text: text, createdAt: (d["createdAt"] as? Double) ?? 0
    )
}


// MARK: - Shared Firestore handle
private var db: Firestore { Firestore.firestore() }

// MARK: - Shared date formatter (avoids repeated allocation)
private let sharedDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df
}()

private func formatTimestamp(_ ts: Double) -> String {
    guard ts > 0 else { return "" }
    return sharedDateFormatter.string(from: Date(timeIntervalSince1970: ts))
}

private let accountDeletionEmail = "360viewofmypeers@gmail.com"

private func openAccountDeletionRequest() {
    let subject = "Delete my account"
    let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Delete%20my%20account"
    let mailtoURLString = "mailto:\(accountDeletionEmail)?subject=\(encodedSubject)"
    guard let url = URL(string: mailtoURLString) else { return }
    UIApplication.shared.open(url)
}

// MARK: - Student list item
private struct StudentListItem: Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - Teacher Subject Tab
struct TeacherSubjectTabView: View {
    @EnvironmentObject private var session: SessionViewModel
    let subject: String

    // All students this teacher has goals/lessons for
    @State private var students: [StudentListItem] = []
    @State private var isLoading = false
    @State private var showAddGoalSheet = false
    @State private var showAddStudentSheet = false
    @State private var statusMsg: String?
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if students.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: subject == "Music" ? "music.note" : "book")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No students yet").foregroundStyle(.secondary)
                        Text("Tap the person badge to create a student account or + to set a goal.")
                            .font(.footnote).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(students) { student in
                            NavigationLink {
                                TeacherStudentDetailView(
                                    subject: subject,
                                    studentId: student.id,
                                    studentName: student.name
                                )
                            } label: {
                                HStack {
                                    Image(systemName: "person.circle").foregroundStyle(.secondary)
                                    Text(student.name).font(.headline)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(subject) Students")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAddStudentSheet = true } label: { Image(systemName: "person.badge.plus") }
                    Button { showAddGoalSheet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddGoalSheet, onDismiss: { Task { await loadStudents() } }) {
                SetGoalView(subject: subject)
            }
            .sheet(isPresented: $showAddStudentSheet, onDismiss: { Task { await loadStudents() } }) {
                CreateStudentAccountView()
            }
            .task { await loadStudents() }
            .refreshable { await loadStudents() }
            .overlay(alignment: .top) {
                if let msg = statusMsg {
                    Text(msg).padding(8).background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func loadStudents() async {
        guard let uid = session.user?.uid else { return }
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        do {
            let linksSnap = try await db.collection("teacher_student_links")
                .whereField("teacherId", isEqualTo: uid)
                .getDocuments()
            var studentMap: [String: String] = [:]
            for d in linksSnap.documents {
                if let sid = d["studentId"] as? String,
                   let name = d["studentName"] as? String {
                    studentMap[sid] = name
                }
            }

            let goalsSnap = try await db.collection("student_goals")
                .whereField("subject", isEqualTo: subject)
                .getDocuments()
            for d in goalsSnap.documents {
                if let sid = d["studentId"] as? String,
                   let name = d["studentName"] as? String {
                    studentMap[sid] = name
                }
            }

            let unique = studentMap.map { StudentListItem(id: $0.key, name: $0.value) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run { students = unique }
        } catch { print("loadStudents error: \(error)") }
    }
}

// MARK: - Create Student Account
struct CreateStudentAccountView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var parentEmail = ""
    @State private var parentPhone = ""
    @State private var studentGrade = "1"
    @State private var errorMessage: String?
    @State private var isCreating = false

    private let studentGrades = (1...8).map { "\($0)" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Student Details") {
                    TextField("Student Name", text: $name)
                    TextField("Student Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Temporary Password", text: $password)
                    Picker("Grade Level", selection: $studentGrade) {
                        ForEach(studentGrades, id: \.self) { grade in
                            Text(grade).tag(grade)
                        }
                    }
                    TextField("Parent Email (optional)", text: $parentEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Parent Phone (optional)", text: $parentPhone)
                        .keyboardType(.phonePad)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Create Student Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await createStudentAccount() }
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(isCreating)
                }
            }
        }
    }

    private func createStudentAccount() async {
        guard let teacher = session.appUser, teacher.role == .teacher else {
            await MainActor.run { errorMessage = "Only teacher accounts can create student accounts." }
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            await MainActor.run { errorMessage = "Please enter the student name." }
            return
        }
        guard !trimmedEmail.isEmpty else {
            await MainActor.run { errorMessage = "Please enter the student email." }
            return
        }
        guard trimmedPassword.count >= 6 else {
            await MainActor.run { errorMessage = "Please use a password with at least 6 characters." }
            return
        }

        await MainActor.run {
            isCreating = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isCreating = false } }

        do {
            let result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: trimmedPassword)
            let studentUser = AppUser(
                id: result.user.uid,
                role: .student,
                name: trimmedName,
                email: trimmedEmail,
                gender: "",
                parentEmail: parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                parentPhone: parentPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : parentPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                studentGrade: studentGrade,
                teacherGradeOrOccupation: nil,
                teacherOtherExplanation: nil
            )

            let db = Firestore.firestore()
            try await db.collection(USERS_COLLECTION).document(result.user.uid).setData(studentUser.asDict)
            try await db.collection("teacher_student_links").document("\(teacher.id)_\(result.user.uid)").setData([
                "teacherId": teacher.id,
                "teacherName": teacher.name,
                "studentId": result.user.uid,
                "studentName": trimmedName,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)

            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { errorMessage = "Could not create student account: \(error.localizedDescription)" }
        }
    }
}

// MARK: - Teacher Student Detail View
struct TeacherStudentDetailView: View {
    @EnvironmentObject private var session: SessionViewModel
    let subject: String
    let studentId: String
    let studentName: String

    @State private var goal: StudentGoal? = nil
    @State private var lessons: [LessonEntry] = []
    @State private var isLoading = false
    @State private var showAddLesson = false
    @State private var showEditGoal = false
    @State private var statusMsg: String?
    var body: some View {
        List {
            // Goal section
            Section {
                if let goal = goal {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🎯 Goal").font(.caption).foregroundStyle(.secondary)
                        Text(goal.goalText).font(.body)
                        if !goal.notes.isEmpty {
                            Text(goal.notes).font(.footnote).foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("Edit Goal") { showEditGoal = true }
                        .font(.footnote)
                } else {
                    Button("Set a Goal") { showEditGoal = true }
                }
            } header: { Text("Goal") }

            // Progress notes section
            Section {
                if lessons.isEmpty {
                    Text("No progress notes yet. Tap + to add one.")
                        .foregroundStyle(.secondary).font(.footnote)
                } else {
                    ForEach(lessons) { lesson in
                        NavigationLink {
                            LessonDetailView(lesson: lesson)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if !lesson.teacherName.isEmpty {
                                    Text("By \(lesson.teacherName)")
                                        .font(.caption).bold().foregroundStyle(.blue)
                                }
                                Text(lesson.progressNote).font(.subheadline).lineLimit(2)
                                Text(formatTimestamp(lesson.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { i in deleteLesson(lessons[i]) }
                    }
                }
            } header: { Text("Progress Notes") }
        }
        .navigationTitle(studentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    EditButton()
                    Button { showAddLesson = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAddLesson, onDismiss: { Task { await loadData() } }) {
            AddProgressNoteView(subject: subject, studentId: studentId, studentName: studentName)
        }
        .sheet(isPresented: $showEditGoal, onDismiss: { Task { await loadData() } }) {
            SetGoalView(subject: subject, existingGoal: goal, preselectedStudentId: studentId, preselectedStudentName: studentName)
        }
        .task { await loadData() }
        .refreshable { await loadData() }
        .overlay(alignment: .top) {
            if let msg = statusMsg {
                Text(msg).padding(8).background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).padding(.top, 8)
            }
        }
    }

    private func loadData() async {
        guard let uid = session.user?.uid else { return }
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        do {
            // Load goal — find any teacher's goal for this student+subject
            let gSnap = try await db.collection("student_goals")
                .whereField("studentId", isEqualTo: studentId)
                .whereField("subject", isEqualTo: subject)
                .getDocuments()
            let loadedGoal = gSnap.documents.compactMap { decodeGoal($0) }.first

            // Load lessons
            let lSnap = try await db.collection("lesson_logs")
                .whereField("studentId", isEqualTo: studentId)
                .whereField("subject", isEqualTo: subject)
                .getDocuments()
            let loadedLessons = lSnap.documents.compactMap { decodeLesson($0) }
                .sorted { $0.createdAt < $1.createdAt }

            await MainActor.run {
                goal = loadedGoal
                lessons = loadedLessons
            }
        } catch { print("loadData error: \(error)") }
    }

    private func deleteLesson(_ entry: LessonEntry) {
        Task {
            do {
                try await db.collection("lesson_logs").document(entry.id).delete()
                await MainActor.run { lessons.removeAll { $0.id == entry.id } }
            } catch {
                await MainActor.run {
                statusMsg = "Delete failed: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusMsg = nil }
            }
            }
        }
    }

}

// MARK: - Set Goal Sheet
struct SetGoalView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    let subject: String
    var existingGoal: StudentGoal? = nil
    var preselectedStudentId: String? = nil
    var preselectedStudentName: String? = nil

    @State private var goalText = ""
    @State private var goalNotes = ""
    @State private var studentId = ""
    @State private var studentName = ""
    @State private var studentList: [StudentListItem] = []
    @State private var isLoadingStudents = false
    @State private var isSaving = false
    @State private var errorMsg: String?
    var body: some View {
        NavigationStack {
            Form {
                if preselectedStudentId == nil {
                    Section("Student") {
                        if isLoadingStudents {
                            ProgressView()
                        } else if studentList.isEmpty {
                            Text("No students found").foregroundStyle(.secondary)
                        } else {
                            Picker("Select Student", selection: $studentId) {
                                Text("Choose…").tag("")
                                ForEach(studentList) { s in Text(s.name).tag(s.id) }
                            }
                        }
                    }
                }
                Section("Goal") {
                    if #available(iOS 16.0, *) {
                        TextField("e.g. Pass Grade 5 Piano Exam", text: $goalText, axis: .vertical)
                            .lineLimit(3...6)
                    } else {
                        TextField("e.g. Pass Grade 5 Piano Exam", text: $goalText)
                    }
                }
                Section("Notes (optional)") {
                    if #available(iOS 16.0, *) {
                        TextField("Any notes about this goal…", text: $goalNotes, axis: .vertical)
                            .lineLimit(2...6)
                    } else {
                        TextField("Any notes about this goal…", text: $goalNotes)
                    }
                }
                if let err = errorMsg {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle(existingGoal == nil ? "Set Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(goalText.trimmingCharacters(in: .whitespaces).isEmpty ||
                                     (preselectedStudentId == nil && studentId.isEmpty))
                    }
                }
            }
            .task {
                if let pid = preselectedStudentId, let pname = preselectedStudentName {
                    studentId = pid; studentName = pname
                } else {
                    await loadStudents()
                }
                if let eg = existingGoal { goalText = eg.goalText; goalNotes = eg.notes }
            }
            .onChange(of: studentId) { newId in
                studentName = studentList.first(where: { $0.id == newId })?.name ?? ""
            }
        }
    }

    private func loadStudents() async {
        await MainActor.run { isLoadingStudents = true }
        defer { Task { @MainActor in isLoadingStudents = false } }
        do {
            let snap = try await db.collection(USERS_COLLECTION)
                .whereField("role", isEqualTo: "student").getDocuments()
            let loaded = snap.documents.compactMap { d -> StudentListItem? in
                guard let name = d["name"] as? String else { return nil }
                return StudentListItem(id: d.documentID, name: name)
            }.sorted { $0.name < $1.name }
            await MainActor.run { studentList = loaded }
        } catch { print("loadStudents error: \(error)") }
    }

    private func save() async {
        guard let teacher = session.appUser else { return }
        let sid = preselectedStudentId ?? studentId
        let sname = preselectedStudentId != nil ? (preselectedStudentName ?? "") : studentName
        guard !sid.isEmpty else {
            await MainActor.run {
                errorMsg = "Please select a student."
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { errorMsg = nil }
            }
            return
        }
        await MainActor.run { isSaving = true }
        defer { Task { @MainActor in isSaving = false } }
        let gid = goalDocId(teacherId: teacher.id, studentId: sid, subject: subject)
        let now = Date().timeIntervalSince1970
        let data: [String: Any] = [
            "teacherId": teacher.id,
            "teacherName": teacher.name,
            "studentId": sid,
            "studentName": sname,
            "subject": subject,
            "goalText": goalText.trimmingCharacters(in: .whitespaces),
            "notes": goalNotes.trimmingCharacters(in: .whitespaces),
            "createdAt": existingGoal?.createdAt ?? now,
            "updatedAt": now
        ]
        do {
            try await db.collection("student_goals").document(gid).setData(data)
            dismiss()
        } catch {
            await MainActor.run {
                errorMsg = "Save failed: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { errorMsg = nil }
            }
        }
    }
}

// MARK: - Add Progress Note Sheet
struct AddProgressNoteView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    let subject: String
    let studentId: String
    let studentName: String

    @State private var authorName = ""
    @State private var progressNote = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var canSave: Bool {
        !authorName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !progressNote.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $authorName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Written by (required)")
                } footer: {
                    Text("This name will appear on the progress note.")
                        .font(.caption)
                }
                Section("Progress Note") {
                    if #available(iOS 16.0, *) {
                        TextField("Describe what was worked on and how the student is progressing…", text: $progressNote, axis: .vertical)
                            .lineLimit(4...10)
                    } else {
                        TextField("Describe progress…", text: $progressNote)
                    }
                }
                Section("Notes (optional)") {
                    if #available(iOS 16.0, *) {
                        TextField("Any extra notes, reminders, or things to follow up on…", text: $notes, axis: .vertical)
                            .lineLimit(2...6)
                    } else {
                        TextField("Any extra notes…", text: $notes)
                    }
                }
                if let err = errorMsg {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Progress Note")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Pre-fill with the logged-in teacher's name but let them edit it
                if authorName.isEmpty {
                    authorName = session.appUser?.name ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
        }
    }

    private func save() async {
        guard let teacher = session.appUser else { return }
        await MainActor.run { isSaving = true }
        defer { Task { @MainActor in isSaving = false } }
        let entry: [String: Any] = [
            "teacherId": teacher.id,
            "teacherName": authorName.trimmingCharacters(in: .whitespaces),
            "studentId": studentId,
            "studentName": studentName,
            "subject": subject,
            "progressNote": progressNote.trimmingCharacters(in: .whitespaces),
            "notes": notes.trimmingCharacters(in: .whitespaces),
            "createdAt": Date().timeIntervalSince1970
        ]
        do {
            try await db.collection("lesson_logs").addDocument(data: entry)
            dismiss()
        } catch {
            await MainActor.run {
                errorMsg = "Save failed: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { errorMsg = nil }
            }
        }
    }
}

// MARK: - Lesson Detail View (with comments)
struct LessonDetailView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    let lesson: LessonEntry

    @State private var comments: [LessonComment] = []
    @State private var newComment = ""
    @State private var isLoadingComments = false
    @State private var isSendingComment = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false

    var isTeacher: Bool { session.appUser?.role == .teacher }

    var body: some View {
        List {
            // Progress note
            Section("Progress Note") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lesson.progressNote).font(.body)
                    Text(formatTimestamp(lesson.createdAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !lesson.notes.isEmpty {
                Section("Notes") {
                    Text(lesson.notes).font(.body)
                }
            }

            // Comments
            Section("Comments") {
                if isLoadingComments {
                    ProgressView()
                } else if comments.isEmpty {
                    Text("No comments yet.").foregroundStyle(.secondary).font(.footnote)
                } else {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.authorName).font(.subheadline).bold()
                                Spacer()
                                Text(formatTimestamp(comment.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(comment.text).font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Add comment
            Section("Add a Comment") {
                HStack(alignment: .bottom, spacing: 8) {
                    if #available(iOS 16.0, *) {
                        TextField("Write a comment…", text: $newComment, axis: .vertical)
                            .lineLimit(1...4)
                    } else {
                        TextField("Write a comment…", text: $newComment)
                    }
                    Button {
                        Task { await postComment() }
                    } label: {
                        if isSendingComment {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(newComment.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                        }
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty || isSendingComment)
                }
            }
        }
        .navigationTitle("Progress Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isTeacher {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .alert("Delete this note?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { Task { await deleteNote() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the progress note and cannot be undone.")
        }
        .task { await loadComments() }
    }

    private func loadComments() async {
        await MainActor.run { isLoadingComments = true }
        defer { Task { @MainActor in isLoadingComments = false } }
        do {
            let snap = try await db.collection("lesson_comments")
                .whereField("lessonId", isEqualTo: lesson.id)
                .getDocuments()
            let loaded = snap.documents.compactMap { decodeComment($0) }
                .sorted { $0.createdAt < $1.createdAt }
            await MainActor.run { comments = loaded }
        } catch { print("loadComments error: \(error)") }
    }

    private func deleteNote() async {
        await MainActor.run { isDeleting = true }
        defer { Task { @MainActor in isDeleting = false } }
        do {
            try await db.collection("lesson_logs").document(lesson.id).delete()
            await MainActor.run { dismiss() }
        } catch { print("deleteNote error: \(error)") }
    }

    private func postComment() async {
        guard let user = session.appUser,
              !newComment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await MainActor.run { isSendingComment = true }
        defer { Task { @MainActor in isSendingComment = false } }
        let data: [String: Any] = [
            "lessonId": lesson.id,
            "authorId": user.id,
            "authorName": user.name,
            "text": newComment.trimmingCharacters(in: .whitespaces),
            "createdAt": Date().timeIntervalSince1970
        ]
        do {
            let ref = try await db.collection("lesson_comments").addDocument(data: data)
            let newC = LessonComment(
                id: ref.documentID, lessonId: lesson.id,
                authorId: user.id, authorName: user.name,
                text: newComment.trimmingCharacters(in: .whitespaces),
                createdAt: Date().timeIntervalSince1970
            )
            await MainActor.run { comments.append(newC); newComment = "" }
        } catch { print("postComment error: \(error)") }
    }

}

// MARK: - Student Subject Tab
struct StudentSubjectTabView: View {
    @EnvironmentObject private var session: SessionViewModel
    let subject: String

    @State private var goals: [StudentGoal] = []
    @State private var isLoading = false
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if goals.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: subject == "Music" ? "music.note" : "book")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No goals set yet").foregroundStyle(.secondary)
                        Text("Your teacher will set your goal here.")
                            .font(.footnote).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(goals) { goal in
                            NavigationLink {
                                StudentProgressView(goal: goal)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(goal.teacherName.isEmpty ? "Teacher" : "Teacher: \(goal.teacherName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("🎯 \(goal.goalText)").font(.subheadline).lineLimit(2)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(subject) Progress")
            .task { await loadGoals() }
            .refreshable { await loadGoals() }
        }
    }

    private func loadGoals() async {
        guard let uid = session.user?.uid else { return }
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        do {
            let snap = try await db.collection("student_goals")
                .whereField("studentId", isEqualTo: uid)
                .whereField("subject", isEqualTo: subject)
                .getDocuments()
            let loaded = snap.documents.compactMap { d -> StudentGoal? in
                return decodeGoal(d)
            }
            await MainActor.run { goals = loaded.sorted { $0.createdAt > $1.createdAt } }
        } catch { print("loadGoals error: \(error)") }
    }
}

// MARK: - Student Progress View
struct StudentProgressView: View {
    @EnvironmentObject private var session: SessionViewModel
    let goal: StudentGoal

    @State private var lessons: [LessonEntry] = []
    @State private var isLoading = false
    var body: some View {
        List {
            Section("Your Goal") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🎯 \(goal.goalText)").font(.body).padding(.vertical, 4)
                    if !goal.notes.isEmpty {
                        Text(goal.notes).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Progress Notes") {
                if isLoading {
                    ProgressView()
                } else if lessons.isEmpty {
                    Text("No progress notes yet.").foregroundStyle(.secondary).font(.footnote)
                } else {
                    ForEach(lessons) { lesson in
                        NavigationLink {
                            LessonDetailView(lesson: lesson)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if !lesson.teacherName.isEmpty {
                                    Text("By \(lesson.teacherName)")
                                        .font(.caption).bold().foregroundStyle(.blue)
                                }
                                Text(lesson.progressNote).font(.subheadline).lineLimit(2)
                                Text(formatTimestamp(lesson.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("My Progress")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLessons() }
        .refreshable { await loadLessons() }
    }

    private func loadLessons() async {
        guard let uid = session.user?.uid else { return }
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        do {
            let snap = try await db.collection("lesson_logs")
                .whereField("studentId", isEqualTo: uid)
                .whereField("subject", isEqualTo: goal.subject)
                .getDocuments()
            let loaded = snap.documents.compactMap { decodeLesson($0) }
                .sorted { $0.createdAt < $1.createdAt }
            await MainActor.run { lessons = loaded }
        } catch { print("loadLessons error: \(error)") }
    }

}

// MARK: - More Tab
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { AccountInfoView() } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
                NavigationLink { ContactUsView() } label: {
                    Label("Contact Us", systemImage: "envelope")
                }
                NavigationLink { NeedSuppliesView() } label: {
                    Label("Need School Supplies?", systemImage: "shippingbox")
                }
            }
            .navigationTitle("More")
        }
    }
}

// MARK: - Contact Us
struct ContactUsView: View {
    private let contactEmail = "360viewofmypeers@gmail.com"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Contact Us").font(.title2).bold()
            Text("Have any questions? We'd love to help.")
            HStack {
                Image(systemName: "envelope")
                if let url = URL(string: "mailto:" + contactEmail) {
                    Link(contactEmail, destination: url)
                } else { Text(contactEmail) }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Contact Us")
    }
}

// MARK: - Need School Supplies
struct NeedSuppliesView: View {
    private let suppliesEmail = "360viewofmypeers@gmail.com"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Need School Supplies?").font(.title2).bold()
            Text("Email us with any requests!")
            HStack {
                Image(systemName: "envelope.badge")
                if let url = URL(string: "mailto:" + suppliesEmail) {
                    Link(suppliesEmail, destination: url)
                } else { Text(suppliesEmail) }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("School Supplies")
    }
}

// MARK: - Root
struct RootView: View {
    @EnvironmentObject var session: SessionViewModel
    var body: some View {
        Group {
            if session.user == nil || session.appUser == nil {
                LandingStartView()
            } else {
                MainTabView()
            }
        }
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .onAppear {
            if let uid = session.user?.uid { InboxBadgeWatcher.shared.start(myId: uid) }
        }
        .onChange(of: session.user?.uid) { newUid in
            if let uid = newUid { InboxBadgeWatcher.shared.start(myId: uid) }
            else { InboxBadgeWatcher.shared.stop() }
        }
    }
}

// MARK: - Compatibility UnavailableView
struct UnavailableView: View {
    let title: String
    let systemImage: String
    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                ContentUnavailableView(title, systemImage: systemImage)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: systemImage).font(.largeTitle)
                    Text(title).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Account Info
struct AccountInfoView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var name = ""
    @State private var email = ""
    @State private var gender = ""
    @State private var parentEmail = ""
    @State private var parentPhone = ""
    @State private var teacherGO = ""
    @State private var teacherOther = ""
    @State private var studentGrade = ""
    @State private var status: String?
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var showEmailReauthAlert = false
    @State private var reauthPassword = ""
    @State private var pendingEmail = ""

    var body: some View {
        NavigationStack {
            Form {
                if let appUser = session.appUser {
                    Section("Profile") {
                        TextField("Name", text: $name)
                            .autocorrectionDisabled()
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        TextField("Gender", text: $gender)
                        Text("Role: \(appUser.role.label)")
                            .foregroundStyle(.secondary)
                    }
                    if appUser.role == .student {
                        Section("Student") {
                            Picker("Grade Level", selection: $studentGrade) {
                                ForEach((1...8).map { "\($0)" }, id: \.self) { grade in
                                    Text(grade).tag(grade)
                                }
                            }
                            TextField("Parent Email", text: $parentEmail)
                            TextField("Parent Phone", text: $parentPhone)
                        }
                    } else {
                        Section("Teacher") {
                            Picker("Grade Level / Occupation", selection: $teacherGO) {
                                ForEach(["9","10","11","12","Current Teacher","Retired Teacher","Other"], id: \.self) { Text($0) }
                            }
                            if teacherGO == "Other" {
                                if #available(iOS 16.0, *) {
                                    TextField("Other (explain)", text: $teacherOther, axis: .vertical)
                                } else {
                                    TextField("Other (explain)", text: $teacherOther)
                                }
                            }
                        }
                    }
                } else {
                    UnavailableView(title: "Loading…", systemImage: "hourglass")
                }
                Section("Actions") {
                    Button { Task { await saveChanges() } } label: {
                        Text("Save Changes").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { session.signOut() } label: {
                        Text("Sign Out").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        openAccountDeletionRequest()
                    } label: {
                        Text("Request Account Deletion").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        HStack {
                            if isDeleting { ProgressView().padding(.trailing, 6) }
                            Text("Delete Account")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if let msg = status {
                    Section { Text(msg).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Account Information")
            .onAppear { populateFromProfile() }
            .alert("Delete Account", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { Task { await handleDeleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete your profile and authentication account. You may need to log in again to confirm.")
            }
            .alert("Confirm Email Change", isPresented: $showEmailReauthAlert) {
                SecureField("Current password", text: $reauthPassword)
                Button("Confirm") { Task { await updateEmailWithReauth() } }
                Button("Cancel", role: .cancel) { reauthPassword = "" }
            } message: {
                Text("Changing your email requires your current password.")
            }
        }
    }

    private func populateFromProfile() {
        guard let u = session.appUser else { return }
        name = u.name
        email = u.email
        gender = u.gender
        if u.role == .student {
            studentGrade = u.studentGrade ?? ""
            parentEmail = u.parentEmail ?? ""
            parentPhone = u.parentPhone ?? ""
        } else {
            teacherGO = u.teacherGradeOrOccupation ?? "9"
            teacherOther = u.teacherOtherExplanation ?? ""
        }
    }

    private func saveChanges() async {
        guard let uid = session.user?.uid, let appUser = session.appUser else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // If email changed, trigger re-auth flow first
        if !trimmedEmail.isEmpty && trimmedEmail != appUser.email {
            await MainActor.run {
                pendingEmail = trimmedEmail
                showEmailReauthAlert = true
            }
            return
        }

        // Build Firestore update payload
        var update: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "gender": gender.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if appUser.role == .student {
            update["studentGrade"] = studentGrade
            update["parentEmail"] = parentEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            update["parentPhone"] = parentPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            update["teacherGradeOrOccupation"] = teacherGO
            if teacherGO == "Other" {
                update["teacherOtherExplanation"] = teacherOther
            } else {
                update["teacherOtherExplanation"] = FieldValue.delete()
            }
        }
        do {
            try await Firestore.firestore().collection(USERS_COLLECTION).document(uid).updateData(update)
            await session.fetchAppUser(uid: uid)
            await MainActor.run {
                populateFromProfile()
                status = "Saved changes."
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { status = nil }
            }
        } catch {
            await MainActor.run {
                status = "Save failed: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { status = nil }
            }
        }
    }

    private func updateEmailWithReauth() async {
        guard let uid = session.user?.uid,
              let currentUser = Auth.auth().currentUser,
              let appUser = session.appUser,
              !pendingEmail.isEmpty,
              !reauthPassword.isEmpty else { return }

        do {
            // Re-authenticate first
            let credential = EmailAuthProvider.credential(
                withEmail: appUser.email,
                password: reauthPassword
            )
            try await currentUser.reauthenticate(with: credential)

            // Update email in Firebase Auth
            try await currentUser.sendEmailVerification(beforeUpdatingEmail: pendingEmail)

            // Update email in Firestore
            let db = Firestore.firestore()
            var update: [String: Any] = [
                "email": pendingEmail,
                "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                "gender": gender.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            if appUser.role == .student {
                update["studentGrade"] = studentGrade
                update["parentEmail"] = parentEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                update["parentPhone"] = parentPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                update["teacherGradeOrOccupation"] = teacherGO
                if teacherGO == "Other" {
                    update["teacherOtherExplanation"] = teacherOther
                } else {
                    update["teacherOtherExplanation"] = FieldValue.delete()
                }
            }
            try await db.collection(USERS_COLLECTION).document(uid).updateData(update)

            await MainActor.run {
                reauthPassword = ""
                pendingEmail = ""
                status = "Verification email sent to \(pendingEmail). Check your inbox to confirm the change."
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { status = nil }
            }
            await session.fetchAppUser(uid: uid)
            await MainActor.run { populateFromProfile() }
        } catch {
            await MainActor.run {
                reauthPassword = ""
                status = "Email update failed: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { status = nil }
            }
        }
    }

    private func handleDeleteAccount() async {
        guard let uid = session.user?.uid else { return }
        await MainActor.run { isDeleting = true }
        defer { Task { await MainActor.run { isDeleting = false } } }
        do {
            let db = Firestore.firestore()
            let b1 = try await db.collection("bookings_v2").whereField("teacherId", isEqualTo: uid).getDocuments()
            let b2 = try await db.collection("bookings_v2").whereField("studentId", isEqualTo: uid).getDocuments()
            var batch = db.batch(); var ops = 0
            for d in (b1.documents + b2.documents) {
                batch.deleteDocument(d.reference); ops += 1
                if ops == 450 { try await batch.commit(); batch = db.batch(); ops = 0 }
            }
            if ops > 0 { try await batch.commit() }
            try await db.collection(USERS_COLLECTION).document(uid).delete()
            do {
                try await Auth.auth().currentUser?.delete()
            } catch {
                await MainActor.run {
                status = "Account data deleted. Re-login to fully remove auth account."
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { status = nil }
            }
            }
            await MainActor.run { status = "Account deleted."; session.signOut() }
        } catch {
            await MainActor.run {
            status = "Delete failed: \(error.localizedDescription)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { status = nil }
        }
        }
    }
}

// MARK: - Chat Module
struct DMUserLite: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var email: String
    var role: String   // "teacher" | "student"
}

func dmThreadId(_ a: String, _ b: String) -> String { [a,b].sorted().joined(separator: "__") }

@MainActor
private func ensureThreadExists(myId: String, other: DMUserLite) async {
    guard !myId.isEmpty, !other.id.isEmpty else { return }
    let db = Firestore.firestore()
    let tid = dmThreadId(myId, other.id)
    let root = db.collection(DM_THREADS).document(tid)
    do {
        try await root.setData([
            "participants": [myId, other.id],
            "createdAt": FieldValue.serverTimestamp(),
            "lastText": "",
            "lastSentAt": FieldValue.serverTimestamp()
        ], merge: true)
        try await root.collection("participants").document(myId).setData([
            "joinedAt": FieldValue.serverTimestamp(),
            "lastSeen": FieldValue.serverTimestamp()
        ], merge: true)
        try await root.collection("participants").document(other.id).setData([
            "joinedAt": FieldValue.serverTimestamp()
        ], merge: true)
    } catch { print("ensureThreadExists error:", error) }
}

struct DMThreadPreview: Identifiable {
    var id: String { otherId }
    let otherId: String
    let otherName: String
    let otherRole: String
    let lastText: String
    let lastSentAt: TimeInterval
    let unreadCount: Int

    func withRole(_ role: String) -> DMThreadPreview {
        DMThreadPreview(otherId: otherId, otherName: otherName, otherRole: role,
                        lastText: lastText, lastSentAt: lastSentAt, unreadCount: unreadCount)
    }
}

final class DMInboxVM: ObservableObject {
    @Published var items: [DMThreadPreview] = []
    private var listener: ListenerRegistration?
    private var roleCache: [String: String] = [:]

    func start(myId: String) {
        stop(); guard !myId.isEmpty else { return }
        let q = Firestore.firestore()
            .collection(DM_INBOX).document(myId)
            .collection("threads")
            .order(by: "lastSentAt", descending: true)
        listener = q.addSnapshotListener { [weak self] snap, err in
            if let err = err { print("inbox listen err:", err); return }
            guard let self = self, let docs = snap?.documents else { return }
            // Build preview rows, then enrich any missing roles from users_v2
            Task { await self.buildAndEnrich(docs: docs) }
        }
    }

    private func buildAndEnrich(docs: [QueryDocumentSnapshot]) async {
        var rows: [DMThreadPreview] = docs.map { d in
            DMThreadPreview(
                otherId: d.documentID,
                otherName: d["otherName"] as? String ?? "",
                otherRole: d["otherRole"] as? String ?? "",
                lastText: d["lastText"] as? String ?? "",
                lastSentAt: (d["lastSentAt"] as? Timestamp)?.dateValue().timeIntervalSince1970
                            ?? (d["lastSentAt"] as? NSNumber)?.doubleValue ?? 0,
                unreadCount: (d["unreadCount"] as? NSNumber)?.intValue ?? 0
            )
        }

        // For any row missing otherRole, look it up from users_v2
        let db = Firestore.firestore()
        for i in rows.indices where rows[i].otherRole.isEmpty {
            let uid = rows[i].otherId
            if let cached = roleCache[uid] {
                rows[i] = rows[i].withRole(cached)
            } else {
                do {
                    let doc = try await db.collection(USERS_COLLECTION).document(uid).getDocument()
                    if let role = doc["role"] as? String {
                        roleCache[uid] = role
                        rows[i] = rows[i].withRole(role)
                    }
                } catch { print("DMInboxVM role lookup error: \(error)") }
            }
        }

        await MainActor.run { self.items = rows }
    }

    func stop() { listener?.remove(); listener = nil; roleCache.removeAll() }
}

struct DMMessage: Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let senderRole: String   // "teacher" | "student"
    let text: String
    let sentAt: TimeInterval
}

final class DMThreadVM: ObservableObject {
    @Published var messages: [DMMessage] = []
    @Published var input: String = ""
    private var listener: ListenerRegistration?
    private var userCache: [String: (name: String, role: String)] = [:]
    var me: String
    var meName: String = ""
    var meRole: String = ""
    let other: DMUserLite
    init(me: String, other: DMUserLite) { self.me = me; self.other = other }

    func start() {
        stop(); guard !me.isEmpty, !other.id.isEmpty else { return }
        // Pre-load both participants' profiles from users_v2 before listening
        Task {
            await loadUserProfiles()
            startListener()
        }
    }

    private func loadUserProfiles() async {
        let db = Firestore.firestore()
        let ids = [me, other.id]
        do {
            for uid in ids {
                let doc = try await db.collection(USERS_COLLECTION).document(uid).getDocument()
                if let data = doc.data(),
                   let name = data["name"] as? String,
                   let role = data["role"] as? String {
                    userCache[uid] = (name: name, role: role)
                }
            }
        } catch { print("DMThreadVM loadUserProfiles error: \(error)") }
    }

    private func startListener() {
        let tid = dmThreadId(me, other.id)
        let q = Firestore.firestore().collection(DM_THREADS).document(tid)
            .collection("messages").order(by: "sentAt", descending: false)
        listener = q.addSnapshotListener { [weak self] snap, err in
            if let err = err { print("DM listen err:", err); return }
            guard let self = self, let docs = snap?.documents else { return }
            let items = docs.map { d -> DMMessage in
                var ts: TimeInterval = 0
                if let t = d["sentAt"] as? Timestamp { ts = t.dateValue().timeIntervalSince1970 }
                else if let n = d["sentAt"] as? NSNumber { ts = n.doubleValue }
                else if let t2 = d["clientSentAt"] as? Timestamp { ts = t2.dateValue().timeIntervalSince1970 }
                else if let n2 = d["clientSentAt"] as? NSNumber { ts = n2.doubleValue }
                let sid = d["senderId"] as? String ?? ""
                // Prefer users_v2 cache; fall back to stored fields on the message
                let name = self.userCache[sid]?.name ?? (d["senderName"] as? String ?? "")
                let role = self.userCache[sid]?.role ?? (d["senderRole"] as? String ?? "")
                return DMMessage(
                    id: d.documentID,
                    senderId: sid,
                    senderName: name,
                    senderRole: role,
                    text: d["text"] as? String ?? "",
                    sentAt: ts
                )
            }
            DispatchQueue.main.async { self.messages = items }
        }
    }

    func stop() { listener?.remove(); listener = nil }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await MainActor.run { self.input = "" }
        let db = Firestore.firestore()
        let tid = dmThreadId(me, other.id)
        let now = Date().timeIntervalSince1970
        await ensureThreadExists(myId: me, other: other)
        do {
            let msgRef = db.collection(DM_THREADS).document(tid).collection("messages").document()
            let batch = db.batch()
            batch.setData(["senderId": me, "senderName": meName, "senderRole": meRole, "text": text, "sentAt": FieldValue.serverTimestamp(), "clientSentAt": now], forDocument: msgRef)
            let threadRef = db.collection(DM_THREADS).document(tid)
            batch.setData(["lastText": text, "lastSentAt": FieldValue.serverTimestamp()], forDocument: threadRef, merge: true)
            let senderInbox = db.collection(DM_INBOX).document(me).collection("threads").document(other.id)
            batch.setData(["otherId": other.id, "otherName": other.name, "otherRole": other.role,
                           "lastText": text, "lastSentAt": FieldValue.serverTimestamp(), "unreadCount": 0],
                          forDocument: senderInbox, merge: true)
            let recvInbox = db.collection(DM_INBOX).document(other.id).collection("threads").document(me)
            batch.setData(["otherId": me, "otherName": meName.isEmpty ? me : meName, "otherRole": meRole,
                           "lastText": text, "lastSentAt": FieldValue.serverTimestamp(),
                           "unreadCount": FieldValue.increment(Int64(1))],
                          forDocument: recvInbox, merge: true)
            try await batch.commit()
        } catch { print("send error: \(error)") }
    }

    func clearAllMessages() async {
        let db = Firestore.firestore()
        let tid = dmThreadId(me, other.id)
        do {
            let snap = try await db.collection(DM_THREADS).document(tid).collection("messages").getDocuments()
            var batch = db.batch(); var ops = 0
            for d in snap.documents {
                batch.deleteDocument(d.reference); ops += 1
                if ops == 450 { try await batch.commit(); batch = db.batch(); ops = 0 }
            }
            if ops > 0 { try await batch.commit() }
            await MainActor.run { self.messages.removeAll() }
        } catch { print("clearAllMessages error:", error) }
    }

    func markRead() {
        Firestore.firestore().collection(DM_INBOX).document(me)
            .collection("threads").document(other.id)
            .setData(["unreadCount": 0], merge: true)
    }
}

// MARK: - Chat Home
struct ChatHomeView: View {
    @StateObject private var inbox = DMInboxVM()
    @EnvironmentObject private var session: SessionViewModel
    @State private var showingUsers = false
    @State private var pendingStart: DMUserLite? = nil

    var body: some View {
        NavigationStack {
            List {
                Section { Button { showingUsers = true } label: { Label("New Message", systemImage: "square.and.pencil") } }
                Section("Conversations") {
                    if inbox.items.isEmpty { Text("No conversations yet").foregroundStyle(.secondary) }
                    ForEach(inbox.items) { row in
                        NavigationLink { DMThreadScreen(otherId: row.otherId, otherName: row.otherName) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(row.otherName.isEmpty ? row.otherId : row.otherName)
                                            .font(.headline)
                                        if !row.otherRole.isEmpty {
                                            Text(row.otherRole.capitalized)
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(row.otherRole == "teacher" ? Color.purple.opacity(0.15) : Color.green.opacity(0.15))
                                                .foregroundStyle(row.otherRole == "teacher" ? .purple : .green)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(row.lastText).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if row.unreadCount > 0 {
                                    Text("\(row.unreadCount)").font(.caption2).padding(6)
                                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(item: $pendingStart) { picked in
                DMThreadScreen(otherId: picked.id, otherName: picked.name)
            }
            .navigationTitle("Direct Messages")
            .sheet(isPresented: $showingUsers) {
                AllUsersPicker { u in pendingStart = u; showingUsers = false }
            }
        }
        .onAppear { if let me = session.user?.uid { inbox.start(myId: me) } }
        .onDisappear { inbox.stop() }
    }
}

// MARK: - All Users Picker
struct AllUsersPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionViewModel
    @State private var teachers: [DMUserLite] = []
    @State private var students: [DMUserLite] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    var onPick: (DMUserLite) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Teachers").tag(0)
                    Text("Students").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.top, 8)

                if selectedTab == 0 {
                    UserSearchList(users: teachers, onPick: { u in onPick(u); dismiss() })
                } else {
                    UserSearchList(users: students, onPick: { u in onPick(u); dismiss() })
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await loadUsers() }
        }
    }

    private func loadUsers() async {
        guard let myId = session.user?.uid else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let snap = try await Firestore.firestore().collection(USERS_COLLECTION).getDocuments()
            var t: [DMUserLite] = []
            var s: [DMUserLite] = []
            for d in snap.documents {
                let id = d.documentID
                guard id != myId,
                      let name = d["name"] as? String,
                      let role = d["role"] as? String else { continue }
                let user = DMUserLite(id: id, name: name, email: d["email"] as? String ?? "", role: role)
                if role == "teacher" { t.append(user) }
                else { s.append(user) }
            }
            let sort: (DMUserLite, DMUserLite) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run {
                teachers = t.sorted(by: sort)
                students = s.sorted(by: sort)
            }
        } catch { print("loadUsers error:", error) }
    }
}

// Searchable user list used inside AllUsersPicker tabs
struct UserSearchList: View {
    let users: [DMUserLite]
    let onPick: (DMUserLite) -> Void
    @State private var searchText = ""

    var filtered: [DMUserLite] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return users }
        return users.filter { $0.name.localizedCaseInsensitiveContains(searchText) ||
                               $0.email.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if users.isEmpty {
                Text("No users found").foregroundStyle(.secondary)
            } else if filtered.isEmpty {
                Text("No results for \"\(searchText)\"").foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { u in
                    Button {
                        onPick(u)
                    } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(u.name).font(.headline).foregroundStyle(.primary)
                                    Text(u.role.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(u.role == "teacher" ? Color.purple.opacity(0.15) : Color.green.opacity(0.15))
                                        .foregroundStyle(u.role == "teacher" ? .purple : .green)
                                        .clipShape(Capsule())
                                }
                                Text(u.email).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by name or email")
    }
}

// MARK: - DM Thread Screen
struct DMThreadScreen: View {
    @EnvironmentObject private var session: SessionViewModel
    let otherId: String
    let otherName: String
    @StateObject private var vm: DMThreadVM
    @State private var showClearMessagesAlert = false

    init(otherId: String, otherName: String) {
        self.otherId = otherId; self.otherName = otherName
        _vm = StateObject(wrappedValue: DMThreadVM(me: "", other: DMUserLite(id: otherId, name: otherName, email: "", role: "")))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.messages) { m in
                        VStack(alignment: m.senderId == vm.me ? .trailing : .leading, spacing: 2) {
                            // Sender name + role label (only for others)
                            if m.senderId != vm.me && !m.senderName.isEmpty {
                                HStack(spacing: 4) {
                                    Text(m.senderName)
                                        .font(.caption).bold()
                                    if !m.senderRole.isEmpty {
                                        Text(m.senderRole.capitalized)
                                            .font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(m.senderRole == "teacher" ? Color.purple.opacity(0.15) : Color.green.opacity(0.15))
                                            .foregroundStyle(m.senderRole == "teacher" ? .purple : .green)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.leading, 6)
                            }
                            HStack(alignment: .bottom) {
                                if m.senderId != vm.me { Spacer(minLength: 40) }
                                Text(m.text).padding(10)
                                    .background(RoundedRectangle(cornerRadius: 16)
                                        .fill(m.senderId == vm.me ? Color.blue.opacity(0.18) : Color.gray.opacity(0.18)))
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7,
                                           alignment: m.senderId == vm.me ? .trailing : .leading)
                                if m.senderId == vm.me { Spacer(minLength: 40) }
                            }
                            Text(Self.timeString(m.sentAt)).font(.caption2).foregroundStyle(.secondary)
                                .padding(m.senderId == vm.me ? .trailing : .leading, 6)
                        }
                    }
                }.padding()
            }
            Divider()
            HStack {
                TextField("Message \(otherName)…", text: $vm.input)
                    .textFieldStyle(.roundedBorder).submitLabel(.send)
                    .onSubmit { Task { await vm.send() } }
                Button { Task { await vm.send() } } label: { Image(systemName: "paperplane.fill") }
                    .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding()
        }
        .navigationTitle(otherName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showClearMessagesAlert = true } label: {
                    Text("Clear all past messages")
                }
            }
        }
        .alert("Clear all messages?", isPresented: $showClearMessagesAlert) {
            Button("Delete All", role: .destructive) { Task { await vm.clearAllMessages() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be deleting all past messages in this conversation.")
        }
        .onAppear {
            guard let me = session.user?.uid else { return }
            vm.me = me
            vm.meName = session.appUser?.name ?? ""
            vm.meRole = session.appUser?.role.rawValue ?? ""
            Task { await ensureThreadExists(myId: me, other: DMUserLite(id: otherId, name: otherName, email: "", role: "")) }
            vm.start(); vm.markRead()
        }
        .onDisappear { vm.stop() }
    }

    private static func timeString(_ ts: TimeInterval) -> String {
        guard ts > 0 else { return "" }
        return sharedDateFormatter.string(from: Date(timeIntervalSince1970: ts))
    }
}

// MARK: - Core Data
@objc(DMMessageEntity)
final class DMMessageEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var threadId: String
    @NSManaged var senderId: String
    @NSManaged var senderName: String
    @NSManaged var text: String
    @NSManaged var sentAt: Double
    @NSManaged var isRead: Bool
}

private func makeDMManagedObjectModel() -> NSManagedObjectModel {
    let model = NSManagedObjectModel()
    let entity = NSEntityDescription()
    entity.name = "DMMessageEntity"
    entity.managedObjectClassName = NSStringFromClass(DMMessageEntity.self)

    func attr(_ name: String, _ type: NSAttributeType, _ optional: Bool = false) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name; a.attributeType = type; a.isOptional = optional
        return a
    }

    entity.properties = [
        attr("id", .stringAttributeType),
        attr("threadId", .stringAttributeType),
        attr("senderId", .stringAttributeType),
        attr("senderName", .stringAttributeType),
        attr("text", .stringAttributeType),
        attr("sentAt", .doubleAttributeType),
        attr("isRead", .booleanAttributeType)
    ]
    model.entities = [entity]
    return model
}

final class PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = makeDMManagedObjectModel()
        container = NSPersistentContainer(name: "DMModel", managedObjectModel: model)
        #if targetEnvironment(simulator)
        let useMemory = true
        #else
        let useMemory = inMemory
        #endif
        if useMemory {
            let desc = NSPersistentStoreDescription()
            desc.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [desc]
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                let desc = NSPersistentStoreDescription()
                desc.type = NSInMemoryStoreType
                self.container.persistentStoreDescriptions = [desc]
                self.container.loadPersistentStores { _, _ in }
                print("CoreData load error (falling back to memory): \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func unreadCount(myId: String) -> Int {
        let ctx = container.viewContext
        let req = NSFetchRequest<NSNumber>(entityName: "DMMessageEntity")
        req.resultType = .countResultType
        req.predicate = NSPredicate(format: "isRead == NO AND senderId != %@", myId)
        do {
            let result = try ctx.fetch(req)
            return result.first?.intValue ?? 0
        } catch { print("unreadCount error: \(error)"); return 0 }
    }


}
