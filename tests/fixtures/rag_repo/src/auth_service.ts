export class AuthService {
  login(username: string, password: string): string {
    if (!username || !password) {
      throw new Error("missing credentials");
    }
    return `token-${username}`;
  }
}

