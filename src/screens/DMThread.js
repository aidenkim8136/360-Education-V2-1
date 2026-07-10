import React, { useEffect, useState } from 'react';
import { View, Text, TextInput, FlatList, TouchableOpacity, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native';
import { getFirebaseAuth, getFirestoreDb } from '../firebaseConfig';
import { collection, addDoc, query, orderBy, onSnapshot } from 'firebase/firestore';
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
    if (!me || !otherId) return;
    const tid = [me.uid, otherId].sort().join('__');
    const q = query(collection(db, 'dm_threads', tid, 'messages'), orderBy('sentAt'));
    const unsub = onSnapshot(q, (snap) => {
      setMessages(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => unsub();
  }, [auth, db, otherId]);

  async function send() {
    if (!input.trim()) return;
    const me = auth.currentUser;
    if (!me || !otherId) return;
    const tid = [me.uid, otherId].sort().join('__');
    await addDoc(collection(db, 'dm_threads', tid, 'messages'), {
      senderId: me.uid,
      senderName: me.displayName || me.email || 'Me',
      text: input.trim(),
      sentAt: Date.now(),
    });
    setInput('');
  }

  return (
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <Text style={styles.title}>{otherName || 'Conversation'}</Text>
      <FlatList
        data={messages}
        keyExtractor={(m) => m.id}
        contentContainerStyle={styles.list}
        renderItem={({ item }) => (
          <View style={styles.bubble}>
            <Text style={styles.author}>{item.senderName || item.senderId}</Text>
            <Text>{item.text}</Text>
          </View>
        )}
      />
      <View style={styles.footer}>
        <TextInput value={input} onChangeText={setInput} placeholder={`Message ${otherName || 'them'}…`} style={styles.input} multiline />
        <TouchableOpacity style={styles.sendButton} onPress={send}><Text style={styles.sendText}>Send</Text></TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 12, backgroundColor: '#fff' },
  title: { fontWeight: '700', fontSize: 18, marginBottom: 8 },
  list: { paddingBottom: 8 },
  bubble: { padding: 10, backgroundColor: '#f3f4f6', marginBottom: 8, borderRadius: 8 },
  author: { fontWeight: '600', marginBottom: 2 },
  footer: { flexDirection: 'row', alignItems: 'flex-end', gap: 8, paddingTop: 8 },
  input: { flex: 1, borderWidth: 1, borderColor: '#d1d5db', padding: 10, borderRadius: 8, maxHeight: 120 },
  sendButton: { backgroundColor: '#2563eb', paddingHorizontal: 12, paddingVertical: 10, borderRadius: 8 },
  sendText: { color: '#fff', fontWeight: '700' },
});
