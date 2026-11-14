import XCTest
@testable import Hatch

/// Свой формат SQL (бета): случаи из согласованного макета и крайние — что запрос по смыслу не меняется.
final class HatchPGTests: XCTestCase {
    private func check(_ input: String, _ expected: String, dialect: String = "sql", case keywordCase: String = "upper",
                       file: StaticString = #filePath, line: UInt = #line) {
        let result = HatchPG.format(input, keywordCase: keywordCase, dialect: dialect)
        XCTAssertEqual(result, expected, "\n--- получилось ---\n\(result ?? "nil")\n", file: file, line: line)
    }

    // MARK: Случаи макета

    func test01UserExample() {
        check("select o.id, o.status, sum(i.price * i.qty) as total from orders o join order_items i on i.order_id = o.id and i.some_field0 = o.some_field0 where o.created_at >= now() - interval '7 days' and (o.status in ('paid', 'shipped') or o.some_field1 = 'someval1' or o.some_field2 = 'someval2' or o.some_field3 = 'someval3') group by o.id, o.status order by total desc limit 20", """
        SELECT o.id
             , o.status
             , SUM(i.price * i.qty) AS total
        FROM orders o
        JOIN order_items i ON TRUE
          AND i.order_id = o.id
          AND i.some_field0 = o.some_field0
        WHERE TRUE
          AND o.created_at >= NOW() - INTERVAL '7 days'
          AND (FALSE
               OR o.status IN ('paid', 'shipped')
               OR o.some_field1 = 'someval1'
               OR o.some_field2 = 'someval2'
               OR o.some_field3 = 'someval3'
          )
        GROUP BY o.id, o.status
        ORDER BY total DESC
        LIMIT 20
        """)
    }

    func test02SingleCondition() {
        check("select id, name from users u join roles r on r.id = u.role_id where u.id = 1", """
        SELECT id
             , name
        FROM users u
        JOIN roles r ON r.id = u.role_id
        WHERE u.id = 1
        """)
    }

    func test03DistinctStarAndStatements() {
        check("select distinct o.status, o.user_id from orders o; select * from t", """
        SELECT DISTINCT o.status
             , o.user_id
        FROM orders o;

        SELECT *
        FROM t
        """)
    }

    func test04TwoOrsStayInline() {
        check("select id from orders where paid and (status = 'new' or status = 'paid')", """
        SELECT id
        FROM orders
        WHERE TRUE
          AND paid
          AND (status = 'new' OR status = 'paid')
        """)
    }

    func test05WholeWhereIsOr() {
        check("select id from users where role = 'admin' or role = 'owner' or is_staff", """
        SELECT id
        FROM users
        WHERE FALSE
          OR role = 'admin'
          OR role = 'owner'
          OR is_staff
        """)
    }

    func test06JoinsAndClickHouse() {
        let sql = "select * from orders o left join users u on u.id = o.user_id left join payments p on p.order_id = o.id and p.status = 'ok'"
        check(sql, """
        SELECT *
        FROM orders o
        LEFT JOIN users u ON u.id = o.user_id
        LEFT JOIN payments p ON TRUE
          AND p.order_id = o.id
          AND p.status = 'ok'
        """)
        check(sql, """
        SELECT *
        FROM orders o
        LEFT JOIN users u ON u.id = o.user_id
        LEFT JOIN payments p ON p.order_id = o.id
          AND p.status = 'ok'
        """, dialect: "clickhouse")
    }

    func test07BetweenAndCase() {
        check("select id, case when qty > 10 and price > 0 then 'bulk' else 'single' end as kind from items where created_at between '2026-01-01' and '2026-02-01' and qty > 0", """
        SELECT id
             , CASE WHEN qty > 10 AND price > 0
               THEN 'bulk'
               ELSE 'single'
             END AS kind
        FROM items
        WHERE TRUE
          AND created_at BETWEEN '2026-01-01' AND '2026-02-01'
          AND qty > 0
        """)
    }

    func test07bCaseWithSeveralWhens() {
        check("select case when a then 1 when b then 2 else 3 end as x, y from t", """
        SELECT CASE WHEN a
               THEN 1
               WHEN b
               THEN 2
               ELSE 3
             END AS x
             , y
        FROM t
        """)
    }

    func test08SubqueryInWhere() {
        check("select id from users where active and id in (select user_id from orders where status = 'paid' and total > 100)", """
        SELECT id
        FROM users
        WHERE TRUE
          AND active
          AND id IN (
            SELECT user_id
            FROM orders
            WHERE TRUE
              AND status = 'paid'
              AND total > 100
          )
        """)
    }

    func test09CTEAndSubqueryInFrom() {
        check("with paid as (select order_id, sum(amount) as total from payments group by order_id), big as (select * from paid where total > 1000) select b.order_id from (select * from big) b", """
        WITH paid AS (
          SELECT order_id
               , SUM(amount) AS total
          FROM payments
          GROUP BY order_id
        )
        , big AS (
          SELECT *
          FROM paid
          WHERE total > 1000
        )
        SELECT b.order_id
        FROM (SELECT * FROM big) b
        """)
    }

    func test10Union() {
        check("select id from a where x = 1 union all select id from b", """
        SELECT id
        FROM a
        WHERE x = 1
        UNION ALL
        SELECT id
        FROM b
        """)
    }

    func test11InsertUpdateDelete() {
        check("insert into orders (id, status) values (1, 'new'), (2, 'paid'); update orders set status = 'paid', paid_at = now() where id = 1 and status = 'new'; delete from orders where id = 1", """
        INSERT INTO orders (id, status)
        VALUES (1, 'new')
             , (2, 'paid');

        UPDATE orders
        SET status = 'paid'
          , paid_at = NOW()
        WHERE TRUE
          AND id = 1
          AND status = 'new';

        DELETE FROM orders
        WHERE id = 1
        """)
    }

    func test12ExistingAnchorAndComments() {
        check("select id -- ключ\nfrom t where 1=1 and a = 1 and b = 2 /* фильтр */", """
        SELECT id -- ключ
        FROM t
        WHERE 1 = 1
          AND a = 1
          AND b = 2 /* фильтр */
        """)
    }

    func test13LongGroupBy() {
        check("select region_name, city_name, count(*) from addresses group by region_name, city_name, district_name, street_name, house_number, apartment_number order by region_name", """
        SELECT region_name
             , city_name
             , COUNT(*)
        FROM addresses
        GROUP BY region_name
               , city_name
               , district_name
               , street_name
               , house_number
               , apartment_number
        ORDER BY region_name
        """)
    }

    func test14WindowAndHaving() {
        check("select user_id, sum(amount) over (partition by user_id order by created_at) as running from payments group by user_id having count(*) > 1 and sum(amount) > 0", """
        SELECT user_id
             , SUM(amount) OVER (PARTITION BY user_id ORDER BY created_at) AS running
        FROM payments
        GROUP BY user_id
        HAVING TRUE
          AND COUNT(*) > 1
          AND SUM(amount) > 0
        """)
    }

    func test15UnsupportedFallsBack() {
        XCTAssertNil(HatchPG.format("create function f() returns int as $$ begin return 1; end $$ language plpgsql"))
        XCTAssertNil(HatchPG.format("select (1 from t"), "скобка не закрыта")
        XCTAssertNil(HatchPG.format("select 'oops from t"), "строка не закрыта")
        XCTAssertNil(HatchPG.format("vacuum analyze orders"))
    }

    // MARK: Крайние случаи

    /// AND и OR в строках, кавычках и комментариях — не условия.
    func testKeywordsInsideStringsAndComments() {
        check("select 'a and b' as \"x or y\" from t where c = 'x and y' and d = 1 -- and e", """
        SELECT 'a and b' AS "x or y"
        FROM t
        WHERE TRUE
          AND c = 'x and y'
          AND d = 1 -- and e
        """)
    }

    /// Однострочный комментарий посреди списка не съедает то, что за ним.
    func testLineCommentInsideList() {
        let result = HatchPG.format("select a, -- первый\n b from t group by a, -- c\n b")
        XCTAssertNotNil(result)
        // проверка на месте: слова те же — значит, комментарий ничего не закомментировал
        XCTAssertTrue(result?.contains("-- первый\n") == true, result ?? "")
    }

    /// AND вперемешку с OR без скобок: по OR (у него приоритет ниже) — смысл виден.
    func testMixedAndOrUsesOrChain() {
        check("select 1 from t where a = 1 and b = 2 or c = 3", """
        SELECT 1
        FROM t
        WHERE FALSE
          OR a = 1 AND b = 2
          OR c = 3
        """)
    }

    func testKeywordCaseLowerAndPreserve() {
        check("SELECT id FROM t WHERE a = 1 AND b = 2", """
        select id
        from t
        where true
          and a = 1
          and b = 2
        """, case: "lower")
        check("Select id From t Where a = 1 And b = 2", """
        Select id
        From t
        Where TRUE
          AND a = 1
          And b = 2
        """, case: "preserve")
    }

    /// ClickHouse: регистр функций не трогаем (toDate и TODATE — разные).
    func testClickHouseFunctionCase() {
        check("select toDate(ts), count() from events", """
        SELECT toDate(ts)
             , count()
        FROM events
        """, dialect: "clickhouse")
    }

    func testPostgresSpecifics() {
        check("select data->>'name', $1::int, E'it\\'s' from t where tags @> '{a}' and id is distinct from $2", """
        SELECT data->>'name'
             , $1::int
             , E'it\\'s'
        FROM t
        WHERE TRUE
          AND tags @> '{a}'
          AND id IS DISTINCT FROM $2
        """, dialect: "postgresql")
    }

    func testDollarQuotedStringStaysWhole() {
        check("select $$a, b and c$$ as s from t", """
        SELECT $$a, b and c$$ AS s
        FROM t
        """)
    }

    func testExistsSubqueryAndNot() {
        check("select id from u where not exists (select 1 from o where o.uid = u.id) and u.active", """
        SELECT id
        FROM u
        WHERE TRUE
          AND NOT EXISTS (
            SELECT FROM o
            WHERE o.uid = u.id
          )
          AND u.active
        """)
    }

    // MARK: Подзапросы и скобки

    /// Короткий подзапрос (один столбец, одна таблица, без условий) — в строку.
    func testShortSubqueryStaysInline() {
        check("delete from retail_reports where guid in (select guid from d_rr);", """
        DELETE FROM retail_reports
        WHERE guid IN (SELECT guid FROM d_rr);
        """)
        check("select a from t where exists (select 1 from u)", """
        SELECT a
        FROM t
        WHERE EXISTS (SELECT FROM u)
        """, dialect: "postgresql")
    }

    /// EXISTS: константа не нужна — `SELECT FROM t`; в MySQL и ClickHouse так нельзя — `SELECT 1` остаётся.
    func testExistsDropsConstantOnlyWhereValid() {
        let query = "select c.guid from c where c.a = 1 or c.b = 2 or exists (select 1 from k where k.guid = c.so)"
        check(query, """
        SELECT c.guid
        FROM c
        WHERE FALSE
          OR c.a = 1
          OR c.b = 2
          OR EXISTS (
            SELECT FROM k
            WHERE k.guid = c.so
          )
        """, dialect: "postgresql")
        let mysql = HatchPG.format(query, dialect: "mysql") ?? ""
        XCTAssertTrue(mysql.contains("SELECT 1\n    FROM k"), mysql)
        let once = HatchPG.format(query, dialect: "postgresql") ?? ""
        XCTAssertEqual(HatchPG.format(once, dialect: "postgresql"), once, "второй раз — то же самое")
    }

    /// Скобки с тремя и больше AND (или AND с подзапросом), в том числе после NOT, — `(TRUE` и `AND …` по строке.
    func testAndGroupAnchoredWithTrue() {
        check("select c.guid from c where c.x = 1 and not (c.rr is not null and c.rr <> '0' and exists (select 1 from r where r.guid = c.rr) and not exists (select 1 from d where d.guid = c.rr));", """
        SELECT c.guid
        FROM c
        WHERE TRUE
          AND c.x = 1
          AND NOT (TRUE
                   AND c.rr IS NOT NULL
                   AND c.rr <> '0'
                   AND EXISTS (
                     SELECT FROM r
                     WHERE r.guid = c.rr
                   )
                   AND NOT EXISTS (
                     SELECT FROM d
                     WHERE d.guid = c.rr
                   )
          );
        """, dialect: "postgresql")
        check("select 1 from t where x = 1 and (a = 1 and b = 2)", """
        SELECT 1
        FROM t
        WHERE TRUE
          AND x = 1
          AND (a = 1 AND b = 2)
        """)
    }

    func testOrGroupWithNestedAnd() {
        check("select 1 from t where x = 1 and (a = 1 or b = 2 and c = 3 or d = 4)", """
        SELECT 1
        FROM t
        WHERE TRUE
          AND x = 1
          AND (FALSE
               OR a = 1
               OR b = 2 AND c = 3
               OR d = 4
          )
        """)
    }

    func testLimitOffsetAndForUpdate() {
        check("select id from jobs where state = 'new' order by id limit 10 offset 5 for update skip locked", """
        SELECT id
        FROM jobs
        WHERE state = 'new'
        ORDER BY id
        LIMIT 10
        OFFSET 5
        FOR UPDATE SKIP LOCKED
        """)
    }

    func testInsertSelectAndOnConflict() {
        check("insert into t (a, b) select a, b from s on conflict (a) do update set b = excluded.b returning a", """
        INSERT INTO t (a, b)
        SELECT a
             , b
        FROM s
        ON CONFLICT (a) DO UPDATE
        SET b = excluded.b
        RETURNING a
        """)
    }

    func testTrailingSemicolonAfterComment() {
        let result = HatchPG.format("select 1 -- x\n;")
        XCTAssertEqual(result, "SELECT 1 -- x\n;")
    }

    /// Любой результат разбирается в те же слова, что вход (за вычетом добавленных TRUE/FALSE/AND/OR).
    func testFormattingIsIdempotentAndSafe() throws {
        let inputs = [
            "select a from t where x between 1 and 2 and y = 3",
            "select case status when 'a' then 1 else 0 end from t",
            "select * from a join b using (id) cross join c where a.x in (1, 2, 3)",
            "with recursive r as (select 1 as n union all select n + 1 from r where n < 3) select * from r",
            "select json_agg(x order by y) filter (where z) from t",
            "select count(*) filter (where a and b) from t where (a or b)",
            "select (select max(id) from t2) as m, x from t where y in (select y from z where q)",
            "select a from t where x = 1 and y = 2 or z = 3 and w = 4",
            "select * from t where (a = 1 or b = 2 or c = 3)",
            "select a, -- первый\n b from t group by a, -- c\n b",
            "-- отчёт\nselect a from t",
        ]
        for input in inputs {
            let once = try XCTUnwrap(HatchPG.format(input), input)
            XCTAssertEqual(HatchPG.format(once), once, "второй раз — то же самое:\n\(once)")
        }
    }

    /// Запрос sqlc: комментарий в начале и комментарий на своей строке перед ON CONFLICT.
    func testSqlcQueryWithComments() {
        let sql = """
        -- name: InsertAction :one
        INSERT INTO actions(guid, type)
        VALUES ($1, $2)
        -- повторный колбэк: updated_at = момент применения
        ON CONFLICT (guid) DO UPDATE SET (type, updated_at) = ($2, now())
        RETURNING obtained_at, updated_at;
        """
        XCTAssertTrue(SyntaxDetector.isSQL(sql), "комментарий в начале — всё равно SQL")
        XCTAssertEqual(SyntaxDetector.detect(sql, allowed: [.sql, .yaml]), .sql)
        check(sql, """
        -- name: InsertAction :one
        INSERT INTO actions(guid, type)
        VALUES ($1, $2)
        -- повторный колбэк: updated_at = момент применения
        ON CONFLICT (guid) DO UPDATE
        SET (type, updated_at) = ($2, NOW())
        RETURNING obtained_at, updated_at;
        """, dialect: "postgresql")
    }
    static let sqlcQuery = """
    -- name: InsertAction :one
    INSERT INTO actions(
        guid, type, id, order_id, client_id,
        payment_system_id, merchant, sum, sbrf_spasibo,
        payment_plan, origin, receipt_url,
        reason, user_id, user_login,
        mpos_terminal_serial_number,
        mpos_merchant_id, mpos_terminal_id, created_at,
        merchant_order_id, obtained_at, updated_at
    )
    VALUES
        (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
            $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
            $21, $22
        )
    -- Повторный колбэк по той же операции: created_at и obtained_at не трогаем, updated_at = момент применения
    ON CONFLICT (guid) DO UPDATE SET (type, id, order_id, client_id,
        payment_system_id, merchant, sum, sbrf_spasibo,
        payment_plan, origin, receipt_url,
        reason, user_id, user_login, mpos_terminal_serial_number,
        mpos_merchant_id, mpos_terminal_id, merchant_order_id, updated_at) = ($2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $20, $22)
    RETURNING obtained_at, updated_at;
    """

    /// Запрос sqlc целиком (как прислал пользователь): длинные списки в скобках — перенос по ширине.
    func testSqlcInsertWithLongLists() {
        check(Self.sqlcQuery, """
        -- name: InsertAction :one
        INSERT INTO actions(
          guid, type, id, order_id, client_id, payment_system_id, merchant, sum,
          sbrf_spasibo, payment_plan, origin, receipt_url, reason, user_id, user_login,
          mpos_terminal_serial_number, mpos_merchant_id, mpos_terminal_id, created_at,
          merchant_order_id, obtained_at, updated_at
        )
        VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17,
          $18, $19, $20, $21, $22
        )
        -- Повторный колбэк по той же операции: created_at и obtained_at не трогаем, updated_at = момент применения
        ON CONFLICT (guid) DO UPDATE
        SET (
          type, id, order_id, client_id, payment_system_id, merchant, sum, sbrf_spasibo,
          payment_plan, origin, receipt_url, reason, user_id, user_login,
          mpos_terminal_serial_number, mpos_merchant_id, mpos_terminal_id,
          merchant_order_id, updated_at
        ) = (
          $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18,
          $20, $22
        )
        RETURNING obtained_at, updated_at;
        """, dialect: "postgresql")
        let once = HatchPG.format(Self.sqlcQuery, dialect: "postgresql") ?? ""
        XCTAssertEqual(HatchPG.format(once, dialect: "postgresql"), once, "второй раз — то же самое")
    }

    /// Короткий список в скобках — по-прежнему в строку.
    func testShortListStaysInline() {
        check("select * from t where id in (1, 2, 3)", """
        SELECT *
        FROM t
        WHERE id IN (1, 2, 3)
        """)
    }
}
