// Storage contracts implemented by the standalone SQLite and file adapters.
export type Row = Record<string, any>;

export interface StatementResult {
  success: boolean;
  results: Row[];
  meta: {changes: number};
}

export interface Statement {
  bind(...values: any[]): Statement;
  all(): Promise<StatementResult>;
  first(): Promise<Row | null>;
  run(): Promise<StatementResult>;
}

export interface Database {
  prepare(sql: string): Statement;
  batch(statements: Statement[]): Promise<StatementResult[]>;
}

export interface DocumentStore {
  put(key: string, data: ArrayBuffer): Promise<void>;
  get(key: string): Promise<{body: BodyInit} | null>;
  delete(key: string): Promise<void>;
}
