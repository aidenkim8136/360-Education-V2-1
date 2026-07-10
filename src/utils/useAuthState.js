import { useEffect, useState } from 'react';
import { getFirestoreDb, getFirebaseAuth } from '../firebaseConfig';
import { doc, onSnapshot } from 'firebase/firestore';
import { onAuthStateChanged } from 'firebase/auth';

export function useAuthState() {
  const [user, setUser] = useState(null);
  const [appUser, setAppUser] = useState(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    const auth = getFirebaseAuth();
    let unsubscribeDoc = null;

    const unsubscribeAuth = onAuthStateChanged(auth, (u) => {
      setUser(u);
      if (unsubscribeDoc) {
        unsubscribeDoc();
        unsubscribeDoc = null;
      }

      if (!u) {
        setAppUser(null);
        setIsReady(true);
        return;
      }

      const db = getFirestoreDb();
      const docRef = doc(db, 'users_v2', u.uid);
      unsubscribeDoc = onSnapshot(docRef, (snap) => {
        setAppUser(snap.exists() ? snap.data() : null);
        setIsReady(true);
      });
    });

    return () => {
      if (unsubscribeDoc) unsubscribeDoc();
      unsubscribeAuth();
    };
  }, []);

  return { user, appUser, isReady };
}
