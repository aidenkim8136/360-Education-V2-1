import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, ActivityIndicator, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { getFirestoreDb, getFirebaseAuth } from '../firebaseConfig';
import { collection, query, where, onSnapshot } from 'firebase/firestore';

export default function StudentSubject({ subject }) {
  const navigation = useNavigation();
  const [goals, setGoals] = useState([]);
  const [loading, setLoading] = useState(true);
  const auth = getFirebaseAuth();
  const db = getFirestoreDb();

  useEffect(() => {
    const user = auth.currentUser;
    if (!user) {
      setLoading(false);
      return;
    }

    const q = query(collection(db, 'student_goals'), where('studentId', '==', user.uid), where('subject', '==', subject));
    const unsub = onSnapshot(q, (snap) => {
      const list = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
      setGoals(list);
      setLoading(false);
    }, (error) => {
      console.warn(error);
      setLoading(false);
    });

    return () => unsub();
  }, [auth, db, subject]);

  const emptyMessage = useMemo(() => subject === 'Music' ? 'No goals set yet. Your teacher will add one here.' : 'No goals set yet.', [subject]);

  if (loading) {
    return <View style={styles.center}><ActivityIndicator size="large" /></View>;
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>{subject} Progress</Text>
      {goals.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyText}>{emptyMessage}</Text>
        </View>
      ) : (
        <FlatList
          data={goals}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <TouchableOpacity style={styles.card} onPress={() => navigation.navigate('LessonDetail', { goal: item })}>
              <Text style={styles.cardTitle}>{item.goalText}</Text>
              {item.teacherName ? <Text style={styles.cardMeta}>Teacher: {item.teacherName}</Text> : null}
              {item.notes ? <Text style={styles.cardNotes}>{item.notes}</Text> : null}
            </TouchableOpacity>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, backgroundColor: '#fff' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  title: { fontSize: 22, fontWeight: '700', marginBottom: 12 },
  emptyState: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 24 },
  emptyText: { textAlign: 'center', color: '#6b7280' },
  card: { padding: 14, borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 10, marginBottom: 10 },
  cardTitle: { fontSize: 15, fontWeight: '600', marginBottom: 4 },
  cardMeta: { color: '#2563eb', marginBottom: 4 },
  cardNotes: { color: '#6b7280' },
});
