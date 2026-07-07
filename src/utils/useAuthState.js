import { useEffect, useState } from 'react';
import { getFirestoreDb } from '../src/firebaseConfig';
import { onAuthStateChanged, getAuth } from 'firebase/auth';
import { doc, onSnapshot } from 'firebase/firestore';

export function useAuthState() {
  const [user, setUser] = useState(null);
  const [appUser, setAppUser] = useState(null);
  useEffect(() => {
    const auth = getAuth();
    const unsub = onAuthStateChanged(auth, u => {
      setUser(u);
      if (u) {
        const db = getFirestoreDb();
        const docRef = doc(db, 'users_v2', u.uid);
        const unsub2 = onSnapshot(docRef, snap => setAppUser(snap.exists() ? snap.data() : null));
        return () => unsub2();
      } else {
        setAppUser(null);
      }
    });
    return () => unsub();
  }, []);
  return { user, appUser };
}
