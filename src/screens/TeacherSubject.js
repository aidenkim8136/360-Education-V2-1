import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, FlatList, Modal, TextInput, TouchableOpacity, Alert, ActivityIndicator } from 'react-native';
import { getFirestoreDb, getFirebaseAuth } from '../firebaseConfig';
import { createUserWithEmailAndPassword } from 'firebase/auth';
import { collection, query, where, onSnapshot, addDoc, setDoc, doc } from 'firebase/firestore';

export default function TeacherSubject({ subject }) {
  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [goalModalVisible, setGoalModalVisible] = useState(false);
  const [studentModalVisible, setStudentModalVisible] = useState(false);
  const [selectedStudentId, setSelectedStudentId] = useState('');
  const [goalText, setGoalText] = useState('');
  const [goalNotes, setGoalNotes] = useState('');
  const [studentName, setStudentName] = useState('');
  const [studentEmail, setStudentEmail] = useState('');
  const [studentPassword, setStudentPassword] = useState('');
  const [studentGrade, setStudentGrade] = useState('1');
  const [parentEmail, setParentEmail] = useState('');
  const [parentPhone, setParentPhone] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const db = getFirestoreDb();
  const auth = getFirebaseAuth();

  useEffect(() => {
    const user = auth.currentUser;
    if (!user) {
      setLoading(false);
      return;
    }

    const linksQuery = query(collection(db, 'teacher_student_links'), where('teacherId', '==', user.uid));
    const unsub = onSnapshot(linksQuery, (snap) => {
      const list = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      setStudents(list);
      setLoading(false);
    }, (error) => {
      console.warn(error);
      setLoading(false);
    });

    return () => unsub();
  }, [auth, db]);

  async function saveGoal() {
    if (!goalText.trim() || !selectedStudentId) {
      Alert.alert('Add a goal and choose a student');
      return;
    }

    setIsSaving(true);
    try {
      const teacher = auth.currentUser;
      if (!teacher) {
        Alert.alert('Please sign in again');
        return;
      }
      const goalDocId = `${teacher.uid}_${selectedStudentId}_${subject}`;
      await setDoc(doc(db, 'student_goals', goalDocId), {
        teacherId: teacher.uid,
        teacherName: teacher.displayName || teacher.email || 'Teacher',
        studentId: selectedStudentId,
        studentName: students.find((s) => s.studentId === selectedStudentId)?.studentName || '',
        subject,
        goalText: goalText.trim(),
        notes: goalNotes.trim(),
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      setGoalModalVisible(false);
      setGoalText('');
      setGoalNotes('');
      setSelectedStudentId('');
      Alert.alert('Goal saved');
    } catch (error) {
      Alert.alert('Could not save goal', error.message || error.toString());
    } finally {
      setIsSaving(false);
    }
  }

  async function createStudentAccount() {
    if (!studentName.trim() || !studentEmail.trim() || !studentPassword.trim()) {
      Alert.alert('Please enter name, email, and password');
      return;
    }

    setIsSaving(true);
    try {
      const teacher = auth.currentUser;
      if (!teacher) {
        Alert.alert('Please sign in again');
        return;
      }
      const userCred = await createUserWithEmailAndPassword(auth, studentEmail.trim().toLowerCase(), studentPassword);
      const uid = userCred.user.uid;
      await setDoc(doc(db, 'users_v2', uid), {
        id: uid,
        role: 'student',
        name: studentName.trim(),
        email: studentEmail.trim().toLowerCase(),
        gender: '',
        parentEmail: parentEmail.trim().toLowerCase() || null,
        parentPhone: parentPhone.trim() || null,
        studentGrade,
        createdAt: Date.now(),
      });
      await setDoc(doc(db, 'teacher_student_links', `${teacher.uid}_${uid}`), {
        teacherId: teacher.uid,
        teacherName: teacher.displayName || teacher.email || 'Teacher',
        studentId: uid,
        studentName: studentName.trim(),
        createdAt: Date.now(),
      });
      setStudentModalVisible(false);
      setStudentName('');
      setStudentEmail('');
      setStudentPassword('');
      setParentEmail('');
      setParentPhone('');
      Alert.alert('Student account created');
    } catch (error) {
      Alert.alert('Could not create student', error.message || error.toString());
    } finally {
      setIsSaving(false);
    }
  }

  if (loading) {
    return <View style={styles.center}><ActivityIndicator size="large" /></View>;
  }

  return (
    <View style={styles.container}>
      <View style={styles.headerRow}>
        <Text style={styles.title}>{subject} Students</Text>
        <View style={styles.headerActions}>
          <TouchableOpacity style={styles.iconButton} onPress={() => setStudentModalVisible(true)}><Text style={styles.iconText}>＋</Text></TouchableOpacity>
          <TouchableOpacity style={styles.iconButton} onPress={() => setGoalModalVisible(true)}><Text style={styles.iconText}>✚</Text></TouchableOpacity>
        </View>
      </View>

      {students.length === 0 ? (
        <View style={styles.emptyState}><Text style={styles.emptyText}>No students yet. Create a student account or add a goal.</Text></View>
      ) : (
        <FlatList data={students} keyExtractor={(item) => item.id} renderItem={({ item }) => <View style={styles.card}><Text style={styles.cardTitle}>{item.studentName}</Text><Text style={styles.cardMeta}>{item.studentId}</Text></View>} />
      )}

      <Modal visible={goalModalVisible} animationType="slide" transparent>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalCard}>
            <Text style={styles.modalTitle}>Set Goal</Text>
            <Text style={styles.label}>Student</Text>
            <View style={styles.pickerBox}>
              {students.map((student) => (
                <TouchableOpacity key={student.studentId} style={[styles.optionButton, selectedStudentId === student.studentId && styles.optionButtonSelected]} onPress={() => setSelectedStudentId(student.studentId)}>
                  <Text style={[styles.optionButtonText, selectedStudentId === student.studentId && styles.optionButtonTextSelected]}>{student.studentName}</Text>
                </TouchableOpacity>
              ))}
            </View>
            <TextInput placeholder="Goal" value={goalText} onChangeText={setGoalText} style={styles.input} />
            <TextInput placeholder="Notes" value={goalNotes} onChangeText={setGoalNotes} style={styles.input} multiline />
            <View style={styles.modalActions}>
              <TouchableOpacity style={styles.secondaryButton} onPress={() => setGoalModalVisible(false)}><Text>Cancel</Text></TouchableOpacity>
              <TouchableOpacity style={styles.primaryButton} onPress={saveGoal} disabled={isSaving}>{isSaving ? <ActivityIndicator color="#fff" /> : <Text style={styles.primaryButtonText}>Save</Text>}</TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal visible={studentModalVisible} animationType="slide" transparent>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalCard}>
            <Text style={styles.modalTitle}>Create Student Account</Text>
            <TextInput placeholder="Student name" value={studentName} onChangeText={setStudentName} style={styles.input} />
            <TextInput placeholder="Student email" value={studentEmail} onChangeText={setStudentEmail} style={styles.input} autoCapitalize="none" keyboardType="email-address" />
            <TextInput placeholder="Temporary password" value={studentPassword} onChangeText={setStudentPassword} style={styles.input} secureTextEntry />
            <TextInput placeholder="Parent email" value={parentEmail} onChangeText={setParentEmail} style={styles.input} autoCapitalize="none" keyboardType="email-address" />
            <TextInput placeholder="Parent phone" value={parentPhone} onChangeText={setParentPhone} style={styles.input} keyboardType="phone-pad" />
            <View style={styles.modalActions}>
              <TouchableOpacity style={styles.secondaryButton} onPress={() => setStudentModalVisible(false)}><Text>Cancel</Text></TouchableOpacity>
              <TouchableOpacity style={styles.primaryButton} onPress={createStudentAccount} disabled={isSaving}>{isSaving ? <ActivityIndicator color="#fff" /> : <Text style={styles.primaryButtonText}>Create</Text>}</TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, backgroundColor: '#fff' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 },
  title: { fontSize: 22, fontWeight: '700' },
  headerActions: { flexDirection: 'row' },
  iconButton: { marginLeft: 8, padding: 8, borderRadius: 999, backgroundColor: '#e5e7eb' },
  iconText: { fontSize: 18 },
  emptyState: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: '#6b7280', textAlign: 'center' },
  card: { padding: 14, borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 10, marginBottom: 10 },
  cardTitle: { fontSize: 15, fontWeight: '600' },
  cardMeta: { color: '#6b7280', marginTop: 4 },
  modalBackdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.35)', justifyContent: 'center', padding: 20 },
  modalCard: { backgroundColor: '#fff', borderRadius: 12, padding: 16 },
  modalTitle: { fontSize: 18, fontWeight: '700', marginBottom: 10 },
  label: { fontWeight: '600', marginBottom: 6 },
  pickerBox: { flexDirection: 'row', flexWrap: 'wrap', marginBottom: 10 },
  optionButton: { borderWidth: 1, borderColor: '#d1d5db', borderRadius: 999, paddingHorizontal: 10, paddingVertical: 6, marginRight: 8, marginBottom: 8 },
  optionButtonSelected: { backgroundColor: '#2563eb', borderColor: '#2563eb' },
  optionButtonText: { color: '#374151' },
  optionButtonTextSelected: { color: '#fff' },
  input: { borderWidth: 1, borderColor: '#d1d5db', padding: 10, borderRadius: 8, marginBottom: 8 },
  modalActions: { flexDirection: 'row', justifyContent: 'flex-end', marginTop: 8 },
  secondaryButton: { paddingVertical: 10, paddingHorizontal: 12, borderRadius: 8, marginRight: 8 },
  primaryButton: { backgroundColor: '#2563eb', paddingVertical: 10, paddingHorizontal: 14, borderRadius: 8, minWidth: 80, alignItems: 'center' },
  primaryButtonText: { color: '#fff', fontWeight: '700' },
});
