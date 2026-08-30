/** @deprecated Use current() instead. */
export function oldApi(): void {}
export function current(): void {}
oldApi();
// @ts-ignore
const value: string = 1;
// @ts-expect-error -- intentional fixture
const other: string = 1;
// @ts-expect-error
const missing: string = 1;
const escaped = value as any;

import { legacy } from "demo"; legacy();
