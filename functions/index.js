// functions/index.js
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

initializeApp();
const db = getFirestore();

function buildPayload({ bookingId, status, title, toTeacher }) {
  const type = status === "confirmed" ? "booking_confirmed" : "booking_rejected";
  const titleText = status === "confirmed"
    ? (toTeacher ? "Booking confirmed ✅" : "Teacher confirmed ✅")
    : (toTeacher ? "Booking rejected ❌" : "Teacher rejected ❌");

  const body = title || "Tutoring session";

  return {
    notification: { title: titleText, body },
    data: { type, bookingId },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
  };
}

async function sendToUser(uid, payload) {
  const user = await db.collection("users_v2").doc(uid).get();
  const token = user.get("fcmToken");
  if (!token) return;
  await getMessaging().send({ token, ...payload });
}

export const notifyOnBookingDecision_v2 = onDocumentWritten(
  { document: "bookings_v2/{bookingId}", region: "us-central1" },
  async (event) => {
    const before = event.data.before.data() || {};
    const after  = event.data.after.data() || {};
    if (!after) return;
    if (before.status === after.status) return;

    const status = after.status;
    if (status !== "confirmed" && status !== "rejected") return;

    const bookingId = event.params.bookingId;
    const actorId   = after.actorId || "";
    const teacherId = after.teacherId || "";
    const studentId = after.studentId || "";
    if (!teacherId || !studentId) return;

    const targetUserId = (actorId === teacherId) ? studentId : teacherId;
    const toTeacher = targetUserId === teacherId;

    const payload = buildPayload({
      bookingId,
      status,
      title: after.title || after.subject || "",
      toTeacher
    });

    try {
      await sendToUser(targetUserId, payload);
    } catch (e) {
      console.error("notifyOnBookingDecision_v2 error", e);
    }
  }
);