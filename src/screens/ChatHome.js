import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, StyleSheet, ActivityIndicator } from 'react-native';
import { getFirestoreDb, getFirebaseAuth } from '../firebaseConfig';
import { collection, getDocs } from 'firebase/firestore';
import { useNavigation } from '@react-navigation/native';

export default function ChatHome() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const db = getFirestoreDb();
  const auth = getFirebaseAuth();
  const navigation = useNavigation();

  useEffect(() => {
    async function loadUsers() {
      try {
        const me = auth.currentUser;
        if (!me) {
          setUsers([]);
          return;
        }
        const snap = await getDocs(collection(db, 'users_v2'));
        const list = snap.docs
          .map((d) => ({ id: d.id, ...d.data() }))
          .filter((user) => user.id !== me?.uid);
        setUsers(list);
      } catch (e) {
        console.warn(e);
      } finally {
        setLoading(false);
      }
    }
    loadUsers();
  }, [auth, db]);

  if (loading) {
    return <View style={styles.center}><ActivityIndicator size="large" /></View>;
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Messages</Text>
      <FlatList
        data={users}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.row} onPress={() => navigation.navigate('DMThread', { otherId: item.id, otherName: item.name || item.email })}>
            <Text style={styles.name}>{item.name || item.email || 'User'}</Text>
            <Text style={styles.role}>{item.role || 'User'}</Text>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, backgroundColor: '#fff' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  title: { fontSize: 22, fontWeight: '700', marginBottom: 12 },
  row: { paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#e5e7eb' },
  name: { fontWeight: '600' },
  role: { color: '#6b7280', marginTop: 2 },
});
