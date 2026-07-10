import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TextInput, TouchableOpacity, ActivityIndicator, Alert } from 'react-native';
import { useRoute } from '@react-navigation/native';
import { getFirebaseAuth, getFirestoreDb } from '../firebaseConfig';
import { addDoc, collection, onSnapshot, query, where } from 'firebase/firestore';
import { useAuthState } from '../utils/useAuthState';

export default function LessonDetailScreen() {
  const route = useRoute();
  const { goal } = route.params || {};
  const [comments, setComments] = useState([]);
  const [notes, setNotes] = useState([]);
  const [draft, setDraft] = useState('');
  const [loading, setLoading] = useState(true);
  const [isPosting, setIsPosting] = useState(false);
  const auth = getFirebaseAuth();
  const db = getFirestoreDb();
  const { appUser } = useAuthState();

  useEffect(() => {
    if (!goal?.studentId) {
      setLoading(false);
      return;
    }

    const lessonQuery = query(collection(db, 'lesson_logs'), where('studentId', '==', goal.studentId), where('subject', '==', goal.subject));
    const lessonUnsub = onSnapshot(lessonQuery, (snap) => {
      const list = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
      setNotes(list);
    });

    const commentsQuery = query(collection(db, 'lesson_comments'), where('lessonId', '==', goal.id));
    const commentUnsub = onSnapshot(commentsQuery, (snap) => {
      const list = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      setComments(list);
      setLoading(false);
    });

    return () => {
      lessonUnsub();
      commentUnsub();
    };
  }, [db, goal]);

  async function postComment() {
    if (!draft.trim() || !auth.currentUser || !goal?.id) return;
    try {
      setIsPosting(true);
      await addDoc(collection(db, 'lesson_comments'), {
        lessonId: goal.id,
        authorId: auth.currentUser.uid,
        authorName: appUser?.name || auth.currentUser.email || 'User',
        text: draft.trim(),
        createdAt: Date.now(),
      });
      setDraft('');
    } catch (error) {
      Alert.alert('Could not post comment', error.message || error.toString());
    } finally {
      setIsPosting(false);
    }
  }

  return (
    <ScrollView style={styles.container}>
      <Text style={styles.title}>{goal?.goalText || 'Goal'}</Text>
      <Text style={styles.meta}>{goal?.teacherName ? `Teacher: ${goal.teacherName}` : 'Teacher goal'}</Text>
      {goal?.notes ? <Text style={styles.notes}>{goal.notes}</Text> : null}

      <Text style={styles.sectionTitle}>Progress notes</Text>
      {notes.length === 0 ? <Text style={styles.empty}>No progress notes yet.</Text> : notes.map((entry) => (
        <View key={entry.id} style={styles.noteCard}>
          <Text style={styles.noteText}>{entry.progressNote || entry.notes}</Text>
          {entry.teacherName ? <Text style={styles.noteMeta}>By {entry.teacherName}</Text> : null}
        </View>
      ))}

      <Text style={styles.sectionTitle}>Comments</Text>
      {loading ? <ActivityIndicator size="small" /> : comments.length === 0 ? <Text style={styles.empty}>No comments yet.</Text> : comments.map((comment) => (
        <View key={comment.id} style={styles.commentCard}>
          <Text style={styles.commentAuthor}>{comment.authorName}</Text>
          <Text>{comment.text}</Text>
        </View>
      ))}

      <TextInput value={draft} onChangeText={setDraft} placeholder="Write a comment" style={styles.input} multiline />
      <TouchableOpacity style={styles.button} onPress={postComment} disabled={isPosting}>
        {isPosting ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>Post Comment</Text>}
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, backgroundColor: '#fff' },
  title: { fontSize: 20, fontWeight: '700', marginBottom: 4 },
  meta: { color: '#2563eb', marginBottom: 8 },
  notes: { color: '#6b7280', marginBottom: 12 },
  sectionTitle: { fontSize: 16, fontWeight: '700', marginTop: 12, marginBottom: 8 },
  empty: { color: '#6b7280', marginBottom: 8 },
  noteCard: { borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 10, padding: 10, marginBottom: 8 },
  noteText: { fontWeight: '600' },
  noteMeta: { color: '#6b7280', marginTop: 4 },
  commentCard: { borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 10, padding: 10, marginBottom: 8 },
  commentAuthor: { fontWeight: '700', marginBottom: 2 },
  input: { borderWidth: 1, borderColor: '#d1d5db', borderRadius: 8, padding: 10, marginTop: 10, minHeight: 80 },
  button: { marginTop: 8, backgroundColor: '#2563eb', paddingVertical: 12, borderRadius: 8, alignItems: 'center' },
  buttonText: { color: '#fff', fontWeight: '700' },
});
