import React, { useEffect, useState } from 'react';
import { View, Text, TextInput, Button, FlatList } from 'react-native';
import { getFirebaseAuth, getFirestoreDb } from '../src/firebaseConfig';
import { collection, addDoc, query, where, orderBy, onSnapshot } from 'firebase/firestore';
import { useRoute } from '@react-navigation/native';

export default function DMThread() {
  const route = useRoute();
  const { otherId, otherName } = route.params || {};
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState('');
  const auth = getFirebaseAuth();
  const db = getFirestoreDb();

  useEffect(() => {
    const me = auth.currentUser;
    if (!me) return;
    const tid = [me.uid, otherId].sort().join('__');
    const q = query(collection(db, 'dm_threads', tid, 'messages'), orderBy('sentAt'));
    const unsub = onSnapshot(q, snap => {
      setMessages(snap.docs.map(d => ({ id: d.id, ...d.data() })));
    });
    return () => unsub();
  }, [otherId]);

  async function send() {
    if (!input.trim()) return;
    const me = auth.currentUser;
    if (!me) return;
    const tid = [me.uid, otherId].sort().join('__');
    await addDoc(collection(db, 'dm_threads', tid, 'messages'), {
      senderId: me.uid,
      senderName: me.displayName || '',
      text: input.trim(),
      sentAt: Date.now()
    });
    setInput('');
  }

  return (
    <View style={{ flex: 1, padding: 8 }}>
      <Text style={{ fontWeight: '700', fontSize: 18, marginBottom: 8 }}>{otherName}</Text>
      <FlatList data={messages} keyExtractor={m => m.id} renderItem={({ item }) => (
        <View style={{ padding: 8, backgroundColor: '#eee', marginBottom: 6, borderRadius: 8 }}>
          <Text style={{ fontWeight: '600' }}>{item.senderName || item.senderId}</Text>
          <Text>{item.text}</Text>
        </View>
      )} />
      <TextInput value={input} onChangeText={setInput} placeholder={`Message ${otherName}…`} style={{ borderWidth:1,borderColor:'#ddd',padding:8,borderRadius:8,marginVertical:8 }} />
      <Button title="Send" onPress={send} />
    </View>
  );
}
