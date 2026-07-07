import React, { useState } from 'react';
import { View, Text, TextInput, Button, StyleSheet, Alert, Picker } from 'react-native';
import { getFirebaseAuth, getFirestoreDb } from '../src/firebaseConfig';
import { createUserWithEmailAndPassword, signInWithEmailAndPassword } from 'firebase/auth';
import { doc, setDoc } from 'firebase/firestore';

export default function AuthScreen({ navigation }) {
  const [isSignUp, setIsSignUp] = useState(true);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [role, setRole] = useState('student');
  const auth = getFirebaseAuth();
  const db = getFirestoreDb();

  async function handlePrimary() {
    if (!email || !password) return Alert.alert('Enter email and password');
    try {
      if (isSignUp) {
        const res = await createUserWithEmailAndPassword(auth, email, password);
        const uid = res.user.uid;
        await setDoc(doc(db, 'users_v2', uid), {
          name: name || 'User',
          email: email.toLowerCase(),
          role: role,
          gender: '',
          createdAt: Date.now()
        });
      } else {
        await signInWithEmailAndPassword(auth, email, password);
      }
      navigation.replace('Main');
    } catch (e) {
      Alert.alert('Auth error', e.message);
    }
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>{isSignUp ? 'Sign Up' : 'Log In'}</Text>
      {isSignUp && (
        <TextInput placeholder="Full name" value={name} onChangeText={setName} style={styles.input} />
      )}
      <TextInput placeholder="Email" value={email} onChangeText={setEmail} style={styles.input} autoCapitalize="none" />
      <TextInput placeholder="Password" value={password} onChangeText={setPassword} secureTextEntry style={styles.input} />
      {isSignUp && (
        <View style={{ width: '100%', marginBottom: 8 }}>
          <Text style={{ marginBottom: 4 }}>I am a…</Text>
          <Picker selectedValue={role} onValueChange={(v) => setRole(v)}>
            <Picker.Item label="Student" value="student" />
            <Picker.Item label="Teacher" value="teacher" />
          </Picker>
        </View>
      )}
      <Button title={isSignUp ? 'Create Account' : 'Log In'} onPress={handlePrimary} />
      <View style={{ height: 10 }} />
      <Button title={isSignUp ? 'I already have an account' : 'Create a new account'} onPress={() => setIsSignUp(!isSignUp)} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, alignItems: 'stretch', justifyContent: 'center' },
  title: { fontSize: 20, fontWeight: '700', marginBottom: 12, textAlign: 'center' },
  input: { borderWidth: 1, borderColor: '#ddd', padding: 10, marginBottom: 8, borderRadius: 6 }
});
