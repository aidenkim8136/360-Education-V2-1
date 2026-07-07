import React, { useEffect, useState } from 'react';
import { View, Text, Button, FlatList } from 'react-native';
import { getFirestoreDb } from '../src/firebaseConfig';
import { collection, getDocs } from 'firebase/firestore';
import { useNavigation } from '@react-navigation/native';

export default function ChatHome() {
  const [users, setUsers] = useState([]);
  const db = getFirestoreDb();
  const navigation = useNavigation();

  useEffect(() => { loadUsers(); }, []);

  async function loadUsers() {
    try {
      const snap = await getDocs(collection(db, 'users_v2'));
      const list = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      setUsers(list);
    } catch (e) { console.warn(e); }
  }

  return (
    <View style={{ flex: 1 }}>
      <FlatList data={users} keyExtractor={item => item.id}
        renderItem={({ item }) => (
          <Button title={item.name || item.email || 'User'} onPress={() => navigation.navigate('DMThread', { otherId: item.id, otherName: item.name })} />
        )} />
    </View>
  );
}
