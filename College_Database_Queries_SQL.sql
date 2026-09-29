SELECT * FROM pr_Students;
SELECT * FROM pr_Professors;
SELECT * FROM pr_Courses;
SELECT * FROM pr_Enrolments;
SELECT * FROM pr_Assignments_Tests;
SELECT * FROM pr_Projects;
SELECT * FROM pr_Midterms;
SELECT * FROM pr_Finals;
SELECT * FROM pr_Assignments_Results;
SELECT * FROM pr_Projects_Results;
SELECT * FROM pr_Midterms_Results;
SELECT * FROM pr_Finals_Results;
SELECT * FROM pr_Grades;

--***************************************************| Hierarchical Queries |*****************************************************

-- Query 1: Create a query to list records in a hierarchy in their proper hierarchical order. 

select level, LPAD(' ',  3*(level - 1), '-') || last_name "Professor", professor_id, supervisor_id
from pr_professors
start with supervisor_id IS NULL
connect by prior professor_id = supervisor_id;

-- Query 2: List last name, professor id and supervisor id, and their level for all professors in the college.

select last_name "Last Name", professor_id "Professor ID", supervisor_id "Supervisor ID", level
from pr_professors
start with supervisor_id IS NULl
connect by prior professor_id = supervisor_id
order by level;

-- Query 3: Query to return the number of levels in the hierarchy.

select max(level)
from pr_professors
start with supervisor_id IS NULL
connect by prior professor_id = supervisor_id;

-- Query 4: Query to return the number of professors under each division

select division "Division", count(*) "Number of Professors"
from pr_professors
start with supervisor_id is null
connect by prior professor_id = supervisor_id
group by division;

-- Query 5: Display all professors that their position's title is "Chair" and "Senior Professor" (level 2 and 3)

select professor_id "Professor ID", last_name "Last Name"
from pr_professors
where level > 1 
and level < 4
start with supervisor_id is null
connect by prior professor_id = supervisor_id;

-- Query 6: Query to list the entire path in the hierarchy for every employee starting from the top manager (root node).

select sys_connect_by_path(last_name, '#') "Hierarchy Tree"
from pr_professors
start with supervisor_id is null
connect by prior professor_id = supervisor_id;

-- Query 7: Assign title to professors based on their level

-- Titles are empty
select last_name, title
from pr_professors;

-- Update the title column
update pr_Professors p
set title = (
    select case level
        when 1 then 'Dean'
        when 2 then 'Chair'
        when 3 then 'Senior Professor'
        when 4 then 'Associate Professor'
        else      'Assistant Professor'
    end
    from pr_Professors h
    where h.professor_id = p.professor_id
    start with h.supervisor_id is null
    connect by prior h.professor_id = h.supervisor_id
);

-- Title column is now filled
select last_name, title
from pr_professors;

-- END OF QUERY 7

--***************************************************| SUBQUERIES, CORRELATED & NON-CORRELATED QUERIES |*****************************************************

-- Query 8: Non-Correlated Subquery - Find students who submitted a project with a grade higher than 80
select student_id, project_id, grade
from pr_projects_results
where grade > 80;

-- Query 9: Correlated Subquery - List students who scored above the average in each assignment
select student_id, assign_id, grade
from pr_assignments_results r1
where grade > (
    select avg(grade)
    from pr_assignments_results r2
    where r1.assign_id = r2.assign_id
);

-- Query 10: Display the total number of absences for each student for the Fall 2023 semster

select s.student_id "Student ID", s.full_name "Full Name", (

    select sum(e.absences)
    from pr_enrolments e
    where s.student_id = e.student_id
) as "Number of Absences"
from pr_students s; 

-- Query 11: Display students that have not been enrolled in any courses for the past 4 Semesters

select s.student_id "Student ID", s.full_name "Full Name"
from pr_students s
where not exists (

    select 1
    from pr_enrolments e join pr_courses c
    on e.course_id = c.course_id
    where s.student_id = e.student_id
    and c.semester in ('FALL 2023', 'SPRING II', 'SPRING I', 'FALL 2022')
);

-- Query 12: Display the students that have registered for less that 4 courses in spring I semester

select s.student_id "Student ID", s.full_name "Full Name"
from pr_students s
where (
    select count(*)
    from pr_enrolments e
    join pr_courses c on e.course_id = c.course_id
    where s.student_id = e.student_id
    and c.semester = 'Spring I'
) < 4;


--***************************************************| User Defined or Oracle Functions & REPORT PRODUCING PROCEDURES  |*****************************************************

-- TASK 1: Procedure to "zero" the grades of assignments and projects that are delivered past their due date
--           by updating the tables

-- Query 13: Procedure to apply penalty (set to 0) to the grade
create or replace procedure apply_penalty is
begin 
    update pr_assignments_results r
    set grade = 0
    where exists (
        select 1
        from pr_assignments_tests a
        where r.assign_id = a.assign_id
        and r.date_delivered > a.due_date
    );

    update pr_projects_results pr
    set grade = 0
    where exists (
        select 1
        from pr_projects p
        where p.project_id = pr.project_id
        and pr.date_delivered > p.due_date
    );
exception
    when no_data_found then
        dbms_output.put_line('No Matching Records Found.');
    when others then
        dbms_output.put_line('Unexpected Error: ' || sqlerrm);
end;

--Run the procedure
begin 
    apply_penalty;
end;

-- Verify the changes before and after procedure at pr_assignments_results
select s.full_name, a.assign_id, a.grade
from pr_students s join pr_assignments_results a
on s.student_id = a.student_id
where a.grade = 0;

-- Verify the changes before and after procedure at pr_projects_results
select s.full_name, p.project_id, p.grade
from pr_students s join pr_projects_results p
on s.student_id = p.student_id
where p.grade = 0;

--************************| END OF TASK 1 |**************************


-- TASK 2: Calculate the final grade for every student for each of his classes

-- Query 14: View to calculate the weighted results from each category
create or replace view pr_Final_Grades_v1 as
select s.Student_ID,
       c.Course_ID,
    nvl(
        (select sum(aR.Grade * AsT.Calculated_Weight / 100) 
         from pr_Assignments_Results aR
         join pr_Assignments_Tests AsT 
         on aR.Assign_ID = AsT.Assign_ID
         where aR.Student_ID = s.Student_ID 
         and AsT.Course_ID = c.Course_ID), 0) as as_results,
    nvl(
        (select sum(pR.Grade * p.Calculated_Weight / 100) 
         from pr_Projects_Results pR
         join pr_Projects p 
         on pR.Project_ID = p.Project_ID
         where pR.Student_ID = s.Student_ID 
         and p.Course_ID = c.Course_ID), 0) as proj_results,
    nvl(
        (select mR.Grade * m.Calculated_Weight / 100
         from pr_Midterms_Results mR
         join pr_Midterms m 
         on mR.Midterms_ID = m.Midterms_ID
         where mR.Student_ID = s.Student_ID 
         and m.Course_ID = c.Course_ID), 0) as mid_results,
    nvl(
        (select fR.Grade * f.Calculated_Weight / 100
         from pr_Finals_Results fR
         join pr_Finals f 
         on fR.Finals_ID = f.Finals_ID
         where fR.Student_ID = s.Student_ID 
         and f.Course_ID = c.Course_ID), 0) as fins_results
from pr_Students s
join pr_Enrolments e 
on s.Student_ID = e.Student_ID
join pr_Courses c 
on c.Course_ID = e.Course_ID;

-- Query 15: Function to calculate the total final grade 
create or replace function calc_final(v_as_r number,
                                         v_proj_r number,
                                         v_mid_r number,
                                         v_fins_r number,
                                         v_stud_id varchar2,
                                         v_cour_id varchar2)
return number is 
    v_final_grade number := 0;
begin
    v_final_grade := v_as_r + v_proj_r + v_mid_r + v_fins_r;

    dbms_output.put_line('Student: ' || v_stud_id || ' - Course: ' || v_cour_id || ' - Final Grade: ' || v_as_r || ' + ' || v_proj_r || ' + ' || v_mid_r || ' + ' || v_fins_r || ' = ' || v_final_grade);
    return v_final_grade; 
exception
    when value_error then
        dbms_output.put_line('invalid input values.');
        return -1;
    when others then
        dbms_output.put_line('unexpected error: ' || sqlerrm);
        return -1;
end calc_final;

-- Query 16: Procedure to execute the function 
create or replace procedure calc_final_proc is
begin
    update pr_grades g
    set grade_percent = (
        select calc_final(
            v.as_results,
            v.proj_results,
            v.mid_results,
            v.fins_results,
            v.student_id,
            v.course_id
        )
        from pr_Final_Grades_v1 v
        where v.student_id = g.student_id
        and v.course_id = g.course_id
    );
exception
    when no_data_found then
        dbms_output.put_line('no matching data found in view.');
    when others then
        dbms_output.put_line('unexpected error: ' || sqlerrm);
end;

-- Run the procedure
begin
    calc_final_proc;
end;

-- To verify results before and after running the procedure
select *
from pr_grades;

--************************| END OF TASK 2 |*************************


-- TASK 3: "Zero" the final grade of a student if he surpassed the limit of absences in a course (default absence limit 10 per course)

-- Query 17: Procedure to update the pr_grades table
create or replace procedure absence_penalty is
begin
    update pr_grades g
    set grade_percent = 0
    where exists (

        select 1
        from pr_enrolments e
        where g.student_id = e.student_id
        and g.course_id = e.course_id
        and e.absences > 10
    );
exception
    when no_data_found then
        dbms_output.put_line('no data found for update.');
    when others then
        dbms_output.put_line('unexpected error: ' || sqlerrm);
end;

-- Query 18: Procedure to update the pr_grades table with cursor and dbms output to display changes
create or replace procedure absence_penalty_cur is
    cursor cur is
        select student_id, course_id, absences
        from pr_enrolments;
begin
    for item in cur loop
        if item.absences > 10 then
            update pr_grades 
            set grade_percent = 0
            where student_id = item.student_id
            and course_id = item.course_id;

            dbms_output.put_line('Student: ' || item.student_id || ' | Course: ' || item.course_id || ' | Absences: ' || item.absences);
        end if;
    end loop;
exception
    when no_data_found then
        dbms_output.put_line('no matching data found.');
    when others then
        dbms_output.put_line('unexpected error: ' || sqlerrm);
end;

-- Run the procedure
begin
    absence_penalty_cur;
end;

-- To verify results before and after running the procedure
select * 
from pr_grades
where grade_percent = 0;

--************************| END OF TASK 3 |*************************


-- TASK 4: Calculate the GPA of each student

-- Query 19: Function for calculating the GPA
create or replace function calc_gpa_func(p_student_id VARCHAR2)
return number is
    v_gpa number;
begin
    select sum(
        CASE
            when g.grade_percent >= 70 then 4.0
            when g.grade_percent >= 65 then 3.67
            when g.grade_percent >= 60 then 3.33
            when g.grade_percent >= 55 then 3.0
            when g.grade_percent >= 50 then 2.67
            when g.grade_percent >= 45 then 2.33
            when g.grade_percent >= 40 then 2.0
            when g.grade_percent >= 35 then 1.67
            when g.grade_percent >= 30 then 1.33
            when g.grade_percent >= 25 then 1.0
            when g.grade_percent >= 20 then 0.67
            when g.grade_percent >= 10 then 0.33
            else 0.0
        end
        * c.credits
    ) / sum(c.credits)
    into v_gpa
    from pr_grades g
    join pr_courses c on g.course_id = c.course_id
    where g.student_id = p_student_id;

    return round(v_gpa, 2);
exception
    when no_data_found then
        dbms_output.put_line('no grades found for student: ' || p_student_id);
        return 0;
    when zero_divide then
        dbms_output.put_line('total credits is zero for student: ' || p_student_id);
        return 0;
    when others then
        dbms_output.put_line('unexpected error for student: ' || p_student_id || ' - ' || sqlerrm);
        return -1;
end;

-- Query 20: Procedure to set the GPA column in pr_Students
create or replace procedure calc_gpa is
    cursor cur is
        select *
        from pr_students;
begin 
    for item in cur loop
        update pr_students
        set GPA = calc_gpa_func(item.student_id)
        where student_id = item.student_id;

        dbms_output.put_line('Student: ' || item.student_id || ' | GPA: ' || item.gpa);
    end loop;
    exception
    when others then
        DBMS_OUTPUT.PUT_LINE('Procedure failed: ' || SQLERRM);
end;

-- Call procedure to fill GPA column
begin
    calc_gpa;
end;

--To verify results before and after the procedure
select student_id, gpa
from pr_students;

--************************| END OF TASK 4 |**********************

-- TASK 5: Alter the status of students to ACTIVE or INACTIVE if they have been enroled in classes during the past 4 semesters

-- Query 21: Procedure to set status
create or replace procedure set_status is
    cursor cur_students is
        select * 
        from pr_students;
    v_count number := 0;
begin 
    for item in cur_students loop
        select count(*)
        into v_count
        from pr_enrolments e
        where e.student_id = item.student_id;

        if v_count > 0 and item.status = 'INACTIVE' then
            update pr_students s
            set status = 'ACTIVE'
            where s.student_id = item.student_id;

            dbms_output.put_line('Student: ' || item.student_id || ' - Status Changed to "ACTIVE"');
        elsif v_count = 0 and item.status = 'ACTIVE' then
            update pr_students s
            set status = 'INACTIVE'
            where s.student_id = item.student_id;

            dbms_output.put_line('Student: ' || item.student_id || ' - Status Changed to "INACTIVE"');
        else
            dbms_output.put_line('Not Applicable to Process this Time!');
        end if;
    end loop;
    exception
    when no_data_found 
        then dbms_output.put_line('No data found for a student during status check.');
    when others
        then dbms_output.put_line('Unexpected error: ' || SQLERRM);
end;

-- Run the status change procedure
begin
    set_status;
end;

--************************| END OF TASK 5 |**********************

-- TASK 6: Delete any students with inactive status from the pr_students table

-- Query 22: Procedure to DELETE the students with status = 'INACTIVE'

create or replace procedure delete_students is
    cursor cur is
        select *
        from pr_students;
begin
    set_status; -- Call the set status procedure to make sure that every students' status is correct
    for item in cur loop
        if item.status not in ('ACTIVE') then
            delete from pr_students s
            where s.student_id = item.student_id;

            dbms_output.put_line('Student: ' || item.student_id || ' Deleted Successfully');
        end if;
    end loop;
exception
    when no_data_found 
        then dbms_output.put_line('No data found - ' || sqlcode || ' - ' || sqlerrm );
    when others
        then dbms_output.put_line('An unanticipated condition has occured ' || sqlcode || ' ' || sqlerrm);
end;

begin
    delete_students;
end;

--************************| END OF TASK 6 |**********************

-- TASK 7: Using a procedure and a cursor show the students that have a GPA higher than 3.5 and insert them in the Dean's List

-- Queries 23
drop table pr_dean_list;
-- Table to hold the dean's list
create table pr_dean_list(
    student_id VARCHAR2(20),
    GPA number,
    constraints pr_dean_list_pk primary key (student_id)
);

-- Query 24: Procedure that checks GPA with explicit cursor and inserts students into table if GPA >= 3.5
create or replace procedure complete_dean_list is
    cursor cur is
        select student_id, gpa
        from pr_students;
    v_id pr_students.student_id%TYPE;
    v_gpa pr_students.gpa%TYPE;
    counter number := 0;
begin
    open cur;
    loop
        fetch cur into v_id, v_gpa;
        if cur%NOTFOUND
            then exit;
        end if;
        if v_gpa >= 3.5
            then insert into pr_dean_list values(v_id, v_gpa);

            dbms_output.put_line('Student: ' || v_id || ' - GPA: ' || v_gpa || ' Added to the Dean List');
            counter := counter +1;
        end if;
    end loop;
    dbms_output.put_line('Total Students Processed: ' || cur%ROWCOUNT);
    dbms_output.put_line('Total Students Added to the List: ' || counter);
    close cur;
exception
    when no_data_found then
        dbms_output.put_line('No students found.');
    when dup_val_on_index then
        dbms_output.put_line('Duplicate entry found for student: ' || v_id);
    when others then
        dbms_output.put_line('Unexpected error: ' || sqlerrm);
end;

-- Run Procedure to process and insert the students
begin
    complete_dean_list;
end;

--************************| END OF TASK 7 |**********************

-- TASK 8: Showcase the students that failed a course with a grade < 40 
--         (print both student_id, full_name, course_id, and course_title of the course they failed)

-- Query 25: Explicit Cursor in an Anonymus Block to make the display
declare
    cursor cur is
        select s.student_id, s.full_name, c.course_id, c.course_title, g.grade_percent
        from pr_students s
        join pr_grades g
        on s.student_id = g.student_id
        join pr_courses c 
        on g.course_id = c.course_id;
begin
    for item in cur loop
        if item.grade_percent < 40 
            then dbms_output.put_line('Student: ' || item.student_id || ' ' || item.full_name || ' - ' || 'Course: ' || item.course_id || ' ' || item.course_title || ' - ' || ' Grade: ' || item.grade_percent);
        end if;
    end loop;
exception
    when no_data_found then
        dbms_output.put_line('No data found.');
    when too_many_rows then
        dbms_output.put_line('Too many rows returned.');
    when others then
        dbms_output.put_line('Unexpected error: ' || sqlerrm);
end;

--************************| END OF TASK 8 |**********************

-- TASK 9: Implicit Cursor in an Anonymus Block to discover the GPA of student with id = 20221414

-- Query 26
declare
    v_student_id pr_students.student_id%TYPE;
    v_full_name pr_students.full_name%TYPE;
    v_gpa pr_students.gpa%TYPE;
begin
    select student_id, full_name, gpa
    into v_student_id, v_full_name, v_gpa
    from pr_students
    where student_id = '20221414';

    dbms_output.put_line('Student ID: ' || v_student_id);
    dbms_output.put_line('Full Name: ' || v_full_name);
    dbms_output.put_line('GPA: ' || v_gpa);
exception
    when no_data_found then
        dbms_output.put_line('No student found with ID 20221414.');
    when too_many_rows then
        dbms_output.put_line('Multiple students found with ID 20221414.');
    when others then
        dbms_output.put_line('Error: ' || sqlerrm);
end;

--************************| END OF TASK 9 |**********************


--***************************************************| TRIGGERS |*****************************************************

-- TASK 10: Auto-assign STATUS value to new students inserted into the pr_Students table

-- Query 27: Trigger to auto-assing the activity status to students (Triggered before insertion in pr_students)
create or replace trigger auto_status_Students
before insert on pr_Students
for each row
begin 
    :new.status := 'INACTIVE';

    dbms_output.put_line('Student: ' || :new.student_id || ' - Status Changed to INACTIVE!');
end auto_status_Students;

-- Data to test the trigger
insert into pr_Students values ('M', 'George Aslanidis', '20220442', '21-Aug-1998', 'Drama Dramas, 23', '6944771290', 'Greece', null, null);

--************************| END OF TASK 10 |**********************


-- TASK 11: Auto-assign title value to new professors inserted into the pr_professors table

-- Query 28: Function to return the title for assignment
create or replace function get_title(p_professor_id VARCHAR2)
return varchar2 is
    v_title varchar2(50);
begin
    select title
    into v_title
    from (
        select professor_id, 
               case level
                   when 1 then 'Dean'
                   when 2 then 'Chair'
                   when 3 then 'Senior Professor'
                   when 4 then 'Associate Professor'
                   else 'Assistant Professor'
               end as title
        from pr_professors
        start with supervisor_id is null
        connect by prior professor_id = supervisor_id
    )
    where professor_id = p_professor_id;

    return v_title;
exception
    when no_data_found then
        return 'Assistant Professor';
    when others then
        return 'Assistant Professor';
end get_title;

-- Query 29: Trigger to auto-assing the titles to professors (Triggered before insertion in pr_Professors)
create or replace trigger auto_title_professors
before insert on pr_professors
for each row
begin 
    :new.title := get_title(:new.professor_id);

    dbms_output.put_line('Professor: ' || :new.professor_id || ' - Title Changed to: ' || :new.title);
end auto_title_professors;

-- Insert new professor into table
insert into pr_Professors values ('PROF-16', 'M', 'Nikos', 'Athanasiadis', 'Humanities and Social Sciences', 'nik@act.edu', '2310429298', 'PROF-3', null);

--************************| END OF TASK 11 |**********************


-- TASK 12: Save any changes inside the pr_courses table in a newly created table

-- Query 30: Create and Drop the new table
drop table pr_courses_audit;

create table pr_courses_audit (
    audit_id number,
    course_id varchar2(20),
    action varchar2(10),
    changed_at date,
    changed_by varchar2(50),
    constraint pr_courses_audit_pk primary key (audit_id)
);

-- Query 31: Sequence that will generate me a unique primary key
create sequence gen_pk 
start with 1 
increment by 1;

-- Query 32: Create the trigger that is going to save the action that took place, for which course it took place, and who changed it
create or replace trigger trg_courses_audit
    after insert or update or delete on pr_courses
    for each row
begin
    begin
        if inserting then
            insert into pr_courses_audit(audit_id, course_id, action, changed_at, changed_by)
            values(gen_pk.nextval, :new.course_id, 'insert', sysdate, user);
            dbms_output.put_line('INSERTED course: ' || :new.course_id);
        elsif updating then
            insert into pr_courses_audit(audit_id, course_id, action, changed_at, changed_by)
            values(gen_pk.nextval, :new.course_id, 'update', sysdate, user);
            dbms_output.put_line('UPDATED course: ' || :new.course_id);
        elsif deleting then
            insert into pr_courses_audit(audit_id, course_id, action, changed_at, changed_by)
            values(gen_pk.nextval, :old.course_id, 'delete', sysdate, user);
            dbms_output.put_line('DELETED course: ' || :old.course_id);
        end if;
    exception
        when others then
            dbms_output.put_line('Trigger error: ' || sqlerrm);
    end;
end trg_courses_audit;


-- Test the trigger
update pr_courses set course_title= 'Updated Course Name'
where course_id = 'ENG 101';

--************************| END OF TASK 12 |**********************