import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Alert, Linking } from 'react-native';
import { getFirebaseAuth } from '../firebaseConfig';
import { signOut } from 'firebase/auth';
import { useAuthState } from '../utils/useAuthState';

export default function More() {
  const { appUser } = useAuthState();
  const auth = getFirebaseAuth();
  const [isSigningOut, setIsSigningOut] = useState(false);

  async function handleSignOut() {
    try {
      setIsSigningOut(true);
      await signOut(auth);
    } catch (e) {
      Alert.alert('Sign out failed', e.message || 'Unable to sign out');
    } finally {
      setIsSigningOut(false);
    }
  }

  function handleDeleteAccount() {
    const email = '360viewofmypeers@gmail.com';
    const subject = 'Delete my account';
    const url = `mailto:${email}?subject=${encodeURIComponent(subject)}`;
    Linking.openURL(url);
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Account</Text>
      <View style={styles.card}>
        <Text style={styles.label}>Name</Text>
        <Text style={styles.value}>{appUser?.name || 'Unknown'}</Text>
        <Text style={styles.label}>Role</Text>
        <Text style={styles.value}>{appUser?.role || 'student'}</Text>
        <Text style={styles.label}>Email</Text>
        <Text style={styles.value}>{appUser?.email || auth.currentUser?.email || ''}</Text>
      </View>

      <TouchableOpacity style={styles.secondaryButton} onPress={handleDeleteAccount}>
        <Text style={styles.secondaryButtonText}>Delete account</Text>
      </TouchableOpacity>
      <TouchableOpacity style={styles.primaryButton} onPress={handleSignOut} disabled={isSigningOut}>
        <Text style={styles.primaryButtonText}>{isSigningOut ? 'Signing out…' : 'Sign out'}</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, backgroundColor: '#fff' },
  title: { fontSize: 22, fontWeight: '700', marginBottom: 12 },
  card: { borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 10, padding: 14, marginBottom: 12 },
  label: { color: '#6b7280', marginTop: 8 },
  value: { fontWeight: '600' },
  primaryButton: { marginTop: 10, backgroundColor: '#2563eb', paddingVertical: 12, borderRadius: 8, alignItems: 'center' },
  primaryButtonText: { color: '#fff', fontWeight: '700' },
  secondaryButton: { marginTop: 8, borderWidth: 1, borderColor: '#d1d5db', paddingVertical: 12, borderRadius: 8, alignItems: 'center' },
  secondaryButtonText: { color: '#374151', fontWeight: '600' },
});
