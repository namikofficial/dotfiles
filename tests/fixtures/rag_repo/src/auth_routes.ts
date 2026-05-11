import { AuthService } from "./auth_service";

const authService = new AuthService();

export async function loginRoute(ctx: { body: { username: string; password: string } }) {
  const token = authService.login(ctx.body.username, ctx.body.password);
  return { token };
}

